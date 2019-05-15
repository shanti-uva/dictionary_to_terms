require 'dictionary_to_terms/processing'
require 'kmaps_engine/progress_bar'

module DictionaryToTerms
  class EtymologyProcessing < Processing
    include KmapsEngine::ProgressBar
    
    def run_etymologies_import
      attrs = { task_code: 'dtt-etymology-import' }
      task = ImportationTask.find_by(attrs)
      task = ImportationTask.create!(attrs) if task.nil?
      self.spreadsheet = task.spreadsheets.find_by(filename: DictionaryToTerms.dictionary_database_yaml['database'])
      self.spreadsheet = task.spreadsheets.create!(filename: DictionaryToTerms.dictionary_database_yaml['database'], imported_at: Time.now) if self.spreadsheet.nil?
      definitions = Dictionary::Etymology.where.not(definition_id: nil)
      n = definitions.size
      i = -1
      definitions.each do |source_etymology|
        i+=1
        source = source_etymology.definition
        term_str = source.term.tibetan_cleanup
        definition_str = source.definition
        source_def = nil
        if source.level == 'head term'
          source_def = source
        else
          sdd = source.sub_definitions.first
          if !sdd.nil?
            source_def = sdd.super_definition
          end
        end
        if source_def.nil?
          term = nil
        else
          term = Feature.find_by_old_pid(source_def.id)
        end
        term = Feature.search_expression(term_str) if term.nil?
        next if term.nil?
        if definition_str.blank?
          etymologies = term.etymologies
        else
          definition = term.definitions.where(content: definition_str).first
          definition = process_definition(term, source) if definition.nil?
          etymologies = definition.etymologies
        end
        options = {content: source_etymology.etymology}
        etymology = etymologies.where(options).first
        next if !etymology.nil? # skip if already imported
        
        etymology = etymologies.create!(options.merge(derivation: source_etymology.derivation))
        subject_associations = etymology.etymology_subject_associations
        add_subject_id(subject_associations, source_etymology.derivation_type_id, 180)
        add_subject_id(subject_associations, source_etymology.etymology_category_id, 182)
        add_subject_text(subject_associations, source_etymology.etymology_type, 182)
        add_subject_id(subject_associations, source_etymology.literary_form_type_id, 186)
        add_subject_text(subject_associations, source_etymology.literary_form, 186)
        add_subject_id(subject_associations, source_etymology.literary_genre_type_id, 119)
        # literary_genre seems to be test data
        add_subject_id(subject_associations, source_etymology.literary_period_type_id, 187)
        add_subject_text(subject_associations, source_etymology.literary_period, 187)
        add_subject_id(subject_associations, source_etymology.loan_language_type_id, 184)
        add_subject_text(subject_associations, source_etymology.loan_language, 184)
        add_subject_id(subject_associations, source_etymology.major_dialect_family_type_id, 638)
        etymology.notes.create!(content: source_etymology.analytical_note) if !source_etymology.analytical_note.blank?
        self.progress_bar(num: i, total: n, current: etymology.id)
      end
    end
  end
end
