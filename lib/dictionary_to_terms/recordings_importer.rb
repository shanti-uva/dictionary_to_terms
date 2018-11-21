module DictionaryToTerms
  class RecordingsImporter
    def self.parse_name(name)
      /^TD_Rec_(?<group>\d+)-(?<subgroup>\d+)_(?<id>\d+)\..*/.match(name)
    end

    def self.map_old_id(old_pid)
      f = Feature.find_by_old_pid(old_pid)
      if f.nil?
        begin
          d = Dictionary::Definition.find(old_pid)
          f = Feature.search_expression(d.term.tibetan_cleanup)
        rescue ActiveRecord::RecordNotFound
          f = nil
        end
      end
      return f.nil? ? nil : f
    end

    def run_recording_import(from:, to:, dialect_id:, filename:, task_code: nil, force: false, source_dir: nil, log_level: nil)
      task_code ||= "dtt-recording-import"
      source_dir ||= Rails.root.join('orig_recordings')
      log = ActiveSupport::Logger.new("log/import_recordings_#{task_code}_#{Rails.env}.log")
      log.level = log_level.nil? ? Rails.logger.level : log_level.to_i
      if filename.nil?
        $std_err.puts "Error: recording importation task - filename required"
        log.fatal { "#{Time.now}: Error: recording importation task - filename required" }
        log.close
        exit false
      end
      start_time = Time.now
      interval = 100

      task = ImportationTask.find_by(task_code: task_code)
      task = ImportationTask.create!(task_code: task_code) if task.nil?
      spreadsheet = task.spreadsheets.find_by(filename: source_dir)
      spreadsheet = task.spreadsheets.create!(filename: source_dir, imported_at: start_time) if spreadsheet.nil?

      dialect = dialect_id.nil? ? nil : SubjectsIntegration::Feature.find(dialect_id)
      if dialect.nil?
        $std_err.puts "Error: incorrect dialect ID: #{dialect_id}"
        log.fatal { "#{Time.now}: Error: incorrect dialect ID: #{dialect_id}" }
        log.close
        exit false
      end
      log.info { "#{Time.now}: #{start_time} From:#{from || "begining"} to:#{to || "end" } for dialect: #{dialect_id}" }

      rows = CSV.read(filename, headers: true, col_sep: "\t")
      from = from.nil? ? 0 : from.to_i
      to = to.nil? ? rows.size : to.to_i
      current = from
      while current < to
        limit = current + interval
        limit = to if limit > to
        limit = rows.size if limit > rows.size
        sid = Spawnling.new do
          log.debug { "#{Time.now}: Spawning sub-process #{Process.pid}." }
          for i in current...limit
            row = rows[i]
            rec_id_str = row['filename_id']
            if rec_id_str.blank?
              log.error { "#{Time.now}: Error: filename id can't be empty in line #{i + 1}" }
              next
            end
            rec_id = rec_id_str.to_i
            log.debug { "Processing record: #{rec_id}" }
            rec_filename = Dir.glob(File.join(source_dir,"*_*#{rec_id}.mp3")).sort.first
            if rec_filename.blank?
              log.error { "#{Time.now}: File for recording: #{rec_id} doesn't exist" }
              next
            end
            old_pid = row['features.old_id']
            if old_pid.blank?
              log.error { "#{Time.now}: Error: old pid can't be empty in line #{i + 1}" }
              next
            end
            term = RecordingsImporter.map_old_id(old_pid)
            if term.nil?
              log.error { "#{Time.now}: Error: dictionary id not found with old_pid #{row['features.old_id']}" }
              next
            end
            curr_recording = Recording.find_by(feature: term, dialect_id: dialect_id)
            if curr_recording.blank?
              log.info { "#{Time.now}: Creating recording for term_id: #{term.fid} and dialect_id: #{dialect_id}" }
              curr_recording = Recording.create(feature: term, dialect_id: dialect_id)
              spreadsheet.imports.create!(item: curr_recording)
            elsif force
              curr_recording.audio_file.purge
              log.warn { "#{Time.now}: Recording exists, it'll be replaced with file No: #{rec_id} - #{rec_filename}" }
            else
              log.warn { "#{Time.now}: Recording already exists, skipping file No: #{rec_id} - #{rec_filename}" }
              next
            end
            begin
              File.open(rec_filename) do |orig_file|
                log.debug { "Attaching file: #{rec_filename}" }
                curr_recording.audio_file.attach(io: orig_file, filename: File.basename(rec_filename))
              end
            rescue Exception => e
              log.error { "#{Time.now}: Error attaching file: #{rec_filename}" }
              log.error { e.message }
              next
            end
          end
        end
        Spawnling.wait([sid])
        current = limit
      end

      end_time = Time.now
      duration = (end_time - start_time) / 1.minute
      log.info { "#{Time.now}: Importation finished #{end_time}; started at #{start_time} with a duration of #{duration} minutes." }
      log.close
    end
  end
end
