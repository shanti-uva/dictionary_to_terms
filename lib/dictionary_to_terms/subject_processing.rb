module DictionaryToTerms
  class DefinitionProcessing
    attr_accessor :spreadsheet
    
    def run_subjects_import(from = nil, to = nil)
      attrs = { task_code: 'dtt-definition-subjects-import' }
      task = ImportationTask.find_by(attrs)
      task = ImportationTask.create!(attrs) if task.nil?
      self.spreadsheet = task.spreadsheets.find_by(filename: DictionaryToTerms.dictionary_database_yaml['database'])
      self.spreadsheet = task.spreadsheets.create!(filename: DictionaryToTerms.dictionary_database_yaml['database'], imported_at: Time.now) if self.spreadsheet.nil?
      definitions = Dictionary::Definition.where(level: 'head term').order(:id)
      definitions = definitions.where(['id >= ?', from]) if !from.blank?
      definitions = definitions.where(['id <= ?', to]) if !to.blank?
      definitions.each do |definition|
        term_str = definition.term
        next if term_str.blank?
        word_str = term_str.tibetan_cleanup
        word = Feature.search_expression(word_str)
        if word.nil?
          STDERR.puts "#{Time.now}: Word #{word_str} (#{definition.id}) not found in already imported terms." if word.nil?
          next
        end
        sid = Spawnling.new do
          begin
            puts "Spawning sub-process #{Process.pid} for processing definition #{definition.id}"
            puts "#{Time.now}: Processing subject associations for TID #{word.fid} (#{definition.id})."
            process_subject_ids(definition, word.subject_term_associations, word.definitions)
          rescue Exception => e
            STDERR.puts e.to_s
          end
        end
        Spawnling.wait([sid])
      end
    end
    
    private
    
    # TODO: WORK ON FREE FLOW TEXT
    def process_subject_keywords(source_def, subject_associations, dest_defs)
    end
    
    def process_subject_ids(source_def, subject_associations, dest_defs)
      add_subject(subject_associations, source_def.grammatical_function_type_id, 5812) # or specifically tibetan: 286?
      add_subject(subject_associations, source_def.language_context_type_id, 185)
      add_subject(subject_associations, source_def.language_type_id, 184)
      add_subject(subject_associations, source_def.literary_form_type_id, 186)
      add_subject(subject_associations, source_def.literary_genre_type_id, 119)
      add_subject(subject_associations, source_def.literary_period_type_id, 187)
      add_subject(subject_associations, source_def.major_dialect_family_type_id, 301)
      add_subject(subject_associations, source_def.register_type_id, 190)
      add_subject(subject_associations, source_def.thematic_classification_type_id, 272)
      source_def.definition_category_associations.each { |a| add_subject(subject_associations, a.category_id, a.category_branch_id) }
      children = source_def.super_definitions.collect{|s| s.sub_definition}.reject(&:nil?)
      children.each do |child|
        source_content = child.definition
        next if source_content.blank?
        dest_def = dest_defs.where(content: source_content).first
        if dest_def.nil?
          STDERR.puts "#{Time.now}: Definition #{child.id} not found!"
          next
        end
        puts "#{Time.now}: Processing subject associations for sub-definition #{child.id}."
        process_subject_ids(child, dest_def.definition_subject_associations, dest_def.children)
      end
    end
    
    def add_subject(collection, subject_id, branch_id)
      if !subject_id.nil?
        options = { subject_id: subject_id }
        association = collection.where(options).first
        if association.nil?
          association = collection.create(options.merge(branch_id: branch_id))
          self.spreadsheet.imports.create!(item: association)
        end
      end
    end
  end
end