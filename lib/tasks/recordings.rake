require 'dictionary_to_terms/recordings_importer'

namespace :dictionary_to_terms do
  namespace :recordings do
    desc "Importation of term recordings form file system.\n"+
      "Syntax: rake dictionary_to_terms:db:import:import_from_fs SOURCE=csv-file-name DIALECT=dialect_id [SOURCE_DIR=path/to/original/recordings] [TASK=task_code] [FROM=row num] [TO=row num] [FORCE=true|false] [LOG_LEVEL=0|1|2|3|4|5] [DAYLIGHT=any_text_to_run_only_after_work_hours]\n\n"+
      "DIALECT can be searched on Subjects app to obtain the id.\n"+
      "FORCE if true the recording will be updated if false(default) it'll ignore the import for that recording."
    task import_from_fs: :environment do
      source= ENV['SOURCE']
      source_dir= ENV['SOURCE_DIR']
      from = Integer(ENV['FROM']) rescue nil
      to = Integer(ENV['TO']) rescue nil
      force = ENV['FORCE'] == 'true' ? true : false
      task_code = ENV['TASK']
      dialect_id = ENV['DIALECT']
      log_level = ENV['LOG_LEVEL']
      daylight = ENV['DAYLIGHT']
      DictionaryToTerms::RecordingsImporter.new("log/import_recordings_#{task_code}_#{Rails.env}.log",log_level).
        run_recording_import(from: from, to: to, dialect_id: dialect_id, filename: source, task_code: task_code, force: force, source_dir: source_dir, daylight: daylight)
    end
  end
end
