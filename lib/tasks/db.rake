require 'dictionary_to_terms/tree_processing'

namespace :dictionary_to_terms do
  namespace :db do |ns|
    desc "Prepare db"
    task :prepare do
      current_scope = ns.scope.path.split(':').first
      target_scope = current_scope=='app' ? 'app:' : ''
      Rake::Task['db:drop'].invoke
      Rake::Task['db:create'].invoke
      Rake::Task["#{target_scope}terms_engine:db:schema:load"].invoke
      Rake::Task["#{target_scope}kmaps_engine:db:seed"].invoke
      Rake::Task["#{target_scope}terms_engine:db:seed"].invoke
      Rake::Task['db:migrate'].invoke
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
    
    namespace :tree do
      desc "Run node classification"
      task classify: :environment do
        DictionaryToTerms::TreeProcessing.new.run_tree_classification
      end
      
      desc "Check old definitions"
      task old_definitions_check: :environment do
        from = ENV['FROM']
        to = ENV['TO']
        fid = ENV['FID']
        if fid.blank?
          DictionaryToTerms::TreeProcessing.new.check_old_definitions(from, to)
        else
          DictionaryToTerms::TreeProcessing.new.check_old_definitions(fid, fid)
        end
      end
      
      desc "Check head terms"
      task head_terms_check: :environment do
        from = ENV['FROM']
        to = ENV['TO']
        fid = ENV['FID']
        if fid.blank?
          DictionaryToTerms::TreeProcessing.new.check_head_terms(from, to)
        else
          DictionaryToTerms::TreeProcessing.new.check_head_terms(fid, fid)
        end
      end
      
      namespace :flatten do
        desc "Run tree flattening into second level"
        task second: :environment do
          DictionaryToTerms::TreeProcessing.new.run_tree_flattening_into_second_level
        end
        
        desc "Run tree flattening into third level"
        task third: :environment do
          DictionaryToTerms::TreeProcessing.new.run_tree_flattening_into_third_level
        end
        
        desc "Run mixed tree flattening"
        task mixed: :environment do
          DictionaryToTerms::TreeProcessing.new.run_tree_flattening_mixed
        end
      end
    end
  end
end