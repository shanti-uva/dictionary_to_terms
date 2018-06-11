require 'dictionary_to_terms/tree_processing'

namespace :dictionary_to_terms do
  namespace :tree do
    desc "Run node classification"
    task classify: :environment do
      DictionaryToTerms::TreeProcessing.new.run_tree_classification
    end

    namespace :check do
      desc "Check old definitions"
      task old_definitions: :environment do
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
      task head_terms: :environment do
        from = ENV['FROM']
        to = ENV['TO']
        fid = ENV['FID']
        if fid.blank?
          DictionaryToTerms::TreeProcessing.new.check_head_terms(from, to)
        else
          DictionaryToTerms::TreeProcessing.new.check_head_terms(fid, fid)
        end
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

      desc "Run fixed tree flattening"
      task fixed: :environment do
        DictionaryToTerms::TreeProcessing.new.run_tree_flattening_fixed
      end
    end
  end
end
