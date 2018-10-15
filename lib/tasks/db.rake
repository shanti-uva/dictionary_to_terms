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
  end
end
