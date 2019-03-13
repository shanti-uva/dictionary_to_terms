require 'kmaps_engine/progress_bar'
module DictionaryToTerms
  class ThubtenPhuntsokDictionaryImporter
    include KmapsEngine::ProgressBar

    INTERVAL = 100

    def import(filename:, from: nil, to: nil, task_code: nil, daylight: nil)
      task_code ||= "dtt-thubten-phuntsok-dictionary-import"
      if filename.nil?
        $stderr.puts "Error: Thubten Phuntsok Dictionary importation task - filename required"
        self.log.fatal { "#{Time.now}: Error: Thubten Phutnsok importation task - filename required" }
        self.close_log
        return false
      end
      start_time = Time.now

      task = ImportationTask.find_by(task_code: task_code)
      task = ImportationTask.create!(task_code: task_code) if task.nil?
      spreadsheet = task.spreadsheets.find_by(filename: filename)
      spreadsheet = task.spreadsheets.create!(filename: filename, imported_at: start_time) if spreadsheet.nil?
      rows = File.readlines(filename)
      current_term = ""
      dictionary = {}
      from = from.nil? ? 0 : from.to_i
      to = to.nil? ? rows.size : to.to_i
      current = from
      ipc_reader, ipc_writer = IO.pipe('ASCII-8BIT')
      ipc_writer.set_encoding('ASCII-8BIT')
      STDOUT.flush
      puts("este es el FROM: #{from} TO: #{to} SIZE: #{rows.size}")
      counterOfNew = 0
      while current < to
        limit = current + INTERVAL
        limit = to if limit > to
        limit = rows.size if limit > rows.size
        ThubtenPhuntsokDictionaryImporter.wait_if_business_hours(daylight)
        sid = Spawnling.new do
          derikCounter = 0
          self.log.debug { "#{Time.now}: Spawning sub-process #{Process.pid}." }
          for i in current...limit
            entry = rows[i].split("\t")
            self.log.debug { "#{Time.now}: processing row[#{i}] : #{rows[i]}" }
            #puts "COUNT: #{entry.count} currentTerm:#{current_term}, definition:#{dictionary[current_term]}\n===>#{entry}" if !line.include? "\t"
            if entry.count > 1 # it contains a entry
              self.log.debug { "#{Time.now}: has an entry" }
              current_term = entry[0]
              dictionaryFeature = Feature.search_expression(current_term.tibetan_cleanup)
              dictionary[current_term] = "Feature: #{dictionaryFeature} || " + entry[1..-1].join(" ")
              counterOfNew += 1 if dictionaryFeature.nil?
              derikCounter += 1 if dictionaryFeature.nil?
            else
              self.log.debug { "#{Time.now}: has an only definition #{entry[0]}" }
              dictionary[current_term] += " #{entry[0]}"
              self.log.debug { "#{Time.now}: definition added" }
            end
            self.progress_bar(num: i, total: to, current: i)
              dictionaryFeature = Feature.search_expression(current_term.tibetan_cleanup)
            puts "Term: #{current_term} Feature: #{dictionaryFeature}"
          end
          puts "This is the end of cycle: #{counterOfNew}"
          puts "This is the end of cycle: #{derikCounter}"
          ipc_hash = { bar: self.bar, num_errors: self.num_errors, valid_point: self.valid_point, counterOfNew: counterOfNew }
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
        counterOfNew = ipc_hash[:counterOfNew].to_i
        current = limit
      end
      ipc_writer.close
      end_time = Time.now
      duration = (end_time - start_time) / 1.minute
      puts "Total number of entries: #{dictionary.count} Total of new Entries: #{counterOfNew}"
      self.log.info { "#{Time.now}: Importation finished #{end_time}; started at #{start_time} with a duration of #{duration} minutes." }
      self.close_log
      STDOUT.flush
    end
  end
end
