require 'dictionary_to_terms/definition_processing'
require 'dictionary_to_terms/subject_processing'
require 'dictionary_to_terms/etymology_processing'
require 'dictionary_to_terms/tree_processing'

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
    desc "Run etymology importation"
    task etymologies: :environment do
<<<<<<< HEAD
      log_level = ENV['LOG_LEVEL']
      DictionaryToTerms::EtymologyProcessing.new("log/import_dtt-etymology-import_#{Rails.env}.log", log_level.nil? ? Rails.logger.level : log_level.to_i).run_etymologies_import
=======
      DictionaryToTerms::EtymologyProcessing.new.run_etymologies_import
>>>>>>> d67f45a... adding importation of etymologies from old dictionary
    end
  end
end
