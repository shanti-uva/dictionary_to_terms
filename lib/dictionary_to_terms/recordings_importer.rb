require 'kmaps_engine/progress_bar'
module DictionaryToTerms
  class RecordingsImporter
    include KmapsEngine::ProgressBar

    INTERVAL = 100

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

    def run_recording_import(from:, to:, dialect_id:, filename:, task_code: nil, force: false, source_dir: nil, daylight: nil)
      task_code ||= "dtt-recording-import"
      source_dir ||= Rails.root.join('orig_recordings')
      if filename.nil?
        $std_err.puts "Error: recording importation task - filename required"
        self.log.fatal { "#{Time.now}: Error: recording importation task - filename required" }
        self.close_log
        return false
      end
      start_time = Time.now

      task = ImportationTask.find_by(task_code: task_code)
      task = ImportationTask.create!(task_code: task_code) if task.nil?
      spreadsheet = task.spreadsheets.find_by(filename: source_dir)
      spreadsheet = task.spreadsheets.create!(filename: source_dir, imported_at: start_time) if spreadsheet.nil?

      dialect = dialect_id.nil? ? nil : SubjectsIntegration::Feature.find(dialect_id)
      if dialect.nil?
        $std_err.puts "Error: incorrect dialect ID: #{dialect_id}"
        self.log.fatal { "#{Time.now}: Error: incorrect dialect ID: #{dialect_id}" }
        self.close_log
        return false
      end
      self.log.info { "#{Time.now}: #{start_time} From:#{from || "begining"} to:#{to || "end" } for dialect: #{dialect_id}" }

      rows = CSV.read(filename, headers: true, col_sep: "\t")
      from = from.nil? ? 0 : from.to_i
      to = to.nil? ? rows.size : to.to_i
      current = from
      ipc_reader, ipc_writer = IO.pipe('ASCII-8BIT')
      ipc_writer.set_encoding('ASCII-8BIT')
      STDOUT.flush
      while current < to
        limit = current + INTERVAL
        limit = to if limit > to
        limit = rows.size if limit > rows.size
        RecordingsImporter.wait_if_business_hours(daylight)
        sid = Spawnling.new do
          self.log.debug { "#{Time.now}: Spawning sub-process #{Process.pid}." }
          for i in current...limit
            row = rows[i]
            rec_id_str = row['filename_id']
            if rec_id_str.blank?
              self.say "Error: filename id can't be empty in line #{i + 1}"
              next
            end
            rec_id = rec_id_str.to_i
            self.log.debug { "Processing record: #{rec_id}" }
            filename = row['filename']
            if !filename.blank?
              rec_filename = File.join(source_dir, filename)
            else
              self.say "Missing filename for recording: #{rec_id}."
              next
            end
            if !rec_filename.exist?
              self.say "File for recording: #{rec_id} doesn't exist"
              next
            end
            old_pid = row['features.old_id']
            if old_pid.blank?
              self.say "Error: old pid can't be empty in line #{i + 1}"
              next
            end
            term = RecordingsImporter.map_old_id(old_pid)
            if term.nil?
              self.say "Error: dictionary id not found with old_pid #{row['features.old_id']}"
              next
            end
            curr_recording = Recording.find_by(feature: term, dialect_id: dialect_id)
            if curr_recording.blank?
              self.log.info { "#{Time.now}: Creating recording for term_id: #{term.fid} and dialect_id: #{dialect_id}" }
              curr_recording = Recording.create(feature: term, dialect_id: dialect_id)
              spreadsheet.imports.create!(item: curr_recording)
            elsif force
              curr_recording.audio_file.purge
              self.say "Recording exists, it'll be replaced with file No: #{rec_id} - #{rec_filename}"
            else
              self.say "Recording already exists, skipping file No: #{rec_id} - #{rec_filename}"
              next
            end
            begin
              self.log.debug { "Attaching file: #{rec_filename}" }
              curr_recording.audio_file.attach(io: File.open(rec_filename), filename: filename, content_type: 'audio/mpeg3')
              self.progress_bar(num: i, total: to, current: rec_id)
            rescue Exception => e
              self.say "Error attaching file: #{rec_filename}\n#{e.message}"
              next
            end
          end
          ipc_hash = { bar: self.bar, num_errors: self.num_errors, valid_point: self.valid_point }
          data = Marshal.dump(ipc_hash)
          ipc_writer.puts(data.length)
          ipc_writer.write(data)
          ipc_writer.flush
          ipc_writer.close
        end
        Spawnling.wait([sid])
        size = ipc_reader.gets
        data = ipc_reader.read(size.to_i)
        ipc_hash = Marshal.load(data)
        self.update_progress_bar(bar: ipc_hash[:bar], num_errors: ipc_hash[:num_errors], valid_point: ipc_hash[:valid_point])
        current = limit
      end
      ipc_writer.close
      end_time = Time.now
      duration = (end_time - start_time) / 1.minute
      self.log.info { "#{Time.now}: Importation finished #{end_time}; started at #{start_time} with a duration of #{duration} minutes." }
      self.close_log
      STDOUT.flush
    end
  end
end
