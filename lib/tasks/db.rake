require 'dictionary_to_terms/tree_processing'

namespace :dictionary_to_terms do
  namespace :db do
    desc "Prepare db"
    task :prepare do
      Rake::Task['db:drop'].invoke
      Rake::Task['db:create'].invoke
      Rake::Task['terms_engine:db:schema:load'].invoke
      Rake::Task['kmaps_engine:db:seed'].invoke
      Rake::Task['terms_engine:db:seed'].invoke
      Feature.remove_by!("tree:#{Feature.uid_prefix}")
    end
    
    namespace :import do
      desc "Run tree importation"
      task tree: :environment do
        DictionaryToTerms::TreeProcessing.new.run_tree_importation
        Rake::Task['kmaps_engine:flare:reindex_all'].invoke
      end
      desc "Run definition importation"
      task definitions: :environment do
        from = ENV['FROM']
        DictionaryToTerms::TreeProcessing.new.run_definition_import(from)
      end
      desc "Run old definition importation"
      task old_definitions: :environment do
        from = ENV['FROM']
        DictionaryToTerms::TreeProcessing.new.run_old_definition_import(from)
      end
    end
    
    namespace :tree do
      desc "Run node classification"
      task classify: :environment do
        DictionaryToTerms::TreeProcessing.new.run_tree_classification
      end
      
      desc "Check old definitions"
      task old_definitions_check: :environment do
        DictionaryToTerms::TreeProcessing.new.check_old_definitions
      end
    end
  end
end