require 'dictionary_to_terms/tree_processing'

namespace :dictionary_to_terms do
  namespace :db do
    desc "Prepare db"
    task :prepare do
      Rake::Task['db:drop'].invoke
      Rake::Task['db:create'].invoke
      Rake::Task['kmaps_engine:db:schema:load'].invoke
      Rake::Task['kmaps_engine:db:seed'].invoke
      Rake::Task['terms_engine:db:seed'].invoke
      Feature.remove_by!("tree:#{Feature.uid_prefix}")
    end
    namespace :tree do
      desc "Run importation"
      task import: :environment do
        DictionaryToTerms::TreeProcessing.new.run_tree_importation
        Rake::Task['kmaps_engine:flare:reindex_all'].invoke
      end
      
      desc "Run node classification"
      task classify: :environment do
        DictionaryToTerms::TreeProcessing.new.run_tree_classification
      end
    end
  end
end