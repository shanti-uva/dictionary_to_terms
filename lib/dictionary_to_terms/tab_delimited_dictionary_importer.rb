require 'kmaps_engine/progress_bar'
module DictionaryToTerms
  class TabDelimitedDictionaryImporter
    include KmapsEngine::ProgressBar

    INTERVAL = 100

    def import(filename:, from: nil, to: nil, task_code: nil, info_source_name: nil, language_code: nil, daylight: nil)
      task_code ||= "dtt-tab-delimited-dictionary-import"
      if filename.nil? || info_source_name.nil? || language_code.nil?
        $stderr.puts "Error: Tab Delimited Dictionary importation task - filename, language_code and info_source_name required"
        self.log.fatal { "#{Time.now}: Error: Tab delimited dictionary importation task - filename, language_code and info_source_name required" }
        self.close_log
        return false
      end
      start_time = Time.now

      task = ImportationTask.find_by(task_code: task_code)
      task = ImportationTask.create!(task_code: task_code) if task.nil?
      spreadsheet = task.spreadsheets.find_by(filename: filename)
      spreadsheet = task.spreadsheets.create!(filename: filename, imported_at: start_time) if spreadsheet.nil?
      rows = File.readlines(filename)

      info_source_attrs = { title: info_source_name }
      info_source = InfoSource.find_by(info_source_attrs)
      info_source = InfoSource.create!(info_source_attrs.merge(code: info_source_name)) if info_source.nil?

      language = Language.get_by_code(language_code)
      current_entry = ""
      current_term = nil
      latest_definition = nil
      dictionary = {}
      from = from.nil? ? 0 : from.to_i
      to = to.nil? ? rows.size : to.to_i
      current = from
      ipc_reader, ipc_writer = IO.pipe('ASCII-8BIT')
      ipc_writer.set_encoding('ASCII-8BIT')
      STDOUT.flush
      counterOfNew = 0
      puts "Current: #{current} to: #{to}"
      while current < to
      puts ">Current: #{current} to: #{to}"
        limit = current + INTERVAL
        limit = to if limit > to
        limit = rows.size if limit > rows.size
        self.wait_if_business_hours(daylight)
        sid = Spawnling.new do
          self.log.debug { "#{Time.now}: Spawning sub-process #{Process.pid}." }
          puts "Going from #{current} to #{limit}"
          for i in current...limit
            entry = rows[i].split("\t")
            puts "PRocessing #{i} === #{entry}"
            self.log.debug { "#{Time.now}: processing row[#{i}] : #{rows[i]}" }
            if entry.count > 1 # it contains a entry
              self.log.debug { "#{Time.now}: Row: #{i}, has an entry. Term: #{entry[0]}" }
              current_entry = entry[0].tibetan_cleanup
              current_term = Feature.search_expression(current_entry)
              # just for debug, this is a term with its definition
              dictionary[current_entry] = "Feature: #{current_term} || " + entry[1..-1].join(" ")
              if current_term.nil?
                # need to implement adding a new term and add the new definition
                self.say "Term missing: #{current_entry}"
                counterOfNew += 1
              else
                definitions = current_term.definitions
                position = definitions.maximum(:position)
                position = position.nil? ? 1 : position + 1
                puts "Adding new definition to term: #{current_term.fid}"
                latest_definition = current_term.definitions.create!({ is_public: true, position: position, language: language, content: entry[1] })
                puts "Added the definition"
                spreadsheet.imports.create!(item: latest_definition)
                if !info_source.nil?
                  citation = latest_definition.citations.create!(info_source: info_source)
                  puts "Creating the citation #{info_source}"
                  spreadsheet.imports.create!(item: citation)
                end
              end
            else
              self.log.debug { "#{Time.now}: Row: #{i}, has only blob data #{entry[0]}" }
              # just for debug, add the blob to the temporary dictionary[current_entry]'s definition
              dictionary[current_entry] += " #{entry[0]}"
              if !current_term.nil? && !latest_definition.nil?
                latest_definition.content += " " + entry[0]
                latest_definition.save!
                self.log.debug { "#{Time.now}: definition added" }
              end
            end
            self.progress_bar(num: i, total: to, current: i)
            current_term = Feature.search_expression(current_entry.tibetan_cleanup)
          end
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
