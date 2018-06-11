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
        DictionaryToTerms::TreeProcessing.new.run_definition_import(from, to)
      else
        DictionaryToTerms::TreeProcessing.new.run_definition_import(fid, fid)
      end
    end
    desc "Run old definition importation"
    task old_definitions: :environment do
      from = ENV['FROM']
      to = ENV['TO']
      fid = ENV['ID']
      if fid.blank?
        DictionaryToTerms::TreeProcessing.new.run_old_definition_import(from, to)
      else
        DictionaryToTerms::TreeProcessing.new.run_old_definition_import(fid, fid)
      end
    end
    desc "Run definition subject importation"
    task subjects: :environment do
      from = ENV['FROM']
      to = ENV['TO']
      fid = ENV['FID']
      if fid.blank?
        DictionaryToTerms::TreeProcessing.new.run_subjects_import(from, to)
      else
        DictionaryToTerms::TreeProcessing.new.run_subjects_import(fid, fid)
      end
    end
  end
end
