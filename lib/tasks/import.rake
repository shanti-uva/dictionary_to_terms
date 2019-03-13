require 'dictionary_to_terms/definition_processing'
require 'dictionary_to_terms/subject_processing'
require 'dictionary_to_terms/tree_processing'
require 'dictionary_to_terms/thubten_phuntsok_dictionary_importer'

namespace :dictionary_to_terms do
  namespace :import do
    desc "Run tree importation"
    task tree: :environment do
      DictionaryToTerms::TreeProcessing.new.run_tree_importation
      Rake::Task['kmaps_engine:flare:reindex_all'].invoke
    end
    desc "Run definition importation"
    task definitions: :environment do
      from = ENV['FROM']
      to = ENV['TO']
      fid = ENV['ID']
      if fid.blank?
        DictionaryToTerms::DefinitionProcessing.new.run_definition_import(from, to)
      else
        DictionaryToTerms::DefinitionProcessing.new.run_definition_import(fid, fid)
      end
    end
    desc "Run old definition importation"
    task old_definitions: :environment do
      from = ENV['FROM']
      to = ENV['TO']
      fid = ENV['ID']
      if fid.blank?
        DictionaryToTerms::DefinitionProcessing.new.run_old_definition_import(from, to)
      else
        DictionaryToTerms::DefinitionProcessing.new.run_old_definition_import(fid, fid)
      end
    end
    desc "Run definition subject importation"
    task subjects: :environment do
      from = ENV['FROM']
      to = ENV['TO']
      fid = ENV['FID']
      if fid.blank?
        DictionaryToTerms::SubjectProcessing.new.run_subjects_import(from, to)
      else
        DictionaryToTerms::SubjectProcessing.new.run_subjects_import(fid, fid)
      end
    end
    desc "Run Thubten Phuntsok definition importation form tab separated file.\n"+
      "Syntax: rake dictionary_to_terms:import:thubten_phuntsok_dictionary FILE=path/to/tab-separated-dictionary [TASK=task_code] [FROM=entry num] [TO=entry num] [LOG_LEVEL=0|1|2|3|4|5] [DAYLIGHT=any_text_to_run_only_after_work_hours]\n\n"+
      "LOG_LEVEL 0 - :debug | 1 - :info | 2 - :warn | 3 - :error | 4 - :fatal | 5 - :unknown "
    task thubten_phuntsok_dictionary: :environment do
      filename = ENV['FILE']
      task_code = ENV['TASK']
      from = ENV['FROM']
      to = ENV['TO']
      log_level = ENV['LOG_LEVEL']
      daylight = ENV['DAYLIGHT']
      task_code ||= "dtt-thubten-phuntsok-dictionary-import"
      DictionaryToTerms::ThubtenPhuntsokDictionaryImporter.new("log/import_thubten_phuntsok_dictionary_#{task_code}_#{Rails.env}.log", log_level).import(filename: filename, from: from, to: to, task_code: task_code, daylight: daylight)
    end
  end
end
