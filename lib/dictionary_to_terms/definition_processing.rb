require 'dictionary_to_terms/processing'

module DictionaryToTerms
  class DefinitionProcessing < Processing
    
    def initialize
      @intersyllabic_tsheg = Unicode::U0F0B
      @tib_alpha = Perspective.get_by_code('tib.alpha')
      @relation_type = FeatureRelationType.get_by_code('is.beginning.of')
    end
    
    def run_old_definition_import(from = nil, to = nil)
      attrs = { task_code: 'dtt-old-definition-import' }
      task = ImportationTask.find_by(attrs)
      task = ImportationTask.create!(attrs) if task.nil?
      self.spreadsheet = task.spreadsheets.find_by(filename: DictionaryToTerms.dictionary_database_yaml['database'])
      self.spreadsheet = task.spreadsheets.create!(filename: DictionaryToTerms.dictionary_database_yaml['database'], imported_at: Time.now) if self.spreadsheet.nil?
      definitions = Dictionary::OldDefinition.all.order(:id)
      definitions = definitions.where(['id >= ?', from]) if !from.blank?
      definitions = definitions.where(['id <= ?', to]) if !to.blank?
      definitions.each do |definition|
        term_str = definition.term
        next if term_str.blank?
        word_str = term_str.tibetan_cleanup
        word = Feature.search_bod_expression(word_str)
        if word.nil?
          word = add_term(definition.id, word_str)
          STDERR.puts "#{Time.now}: Word #{word_str} (#{definition.id}) not found and could not be added." if word.nil?
        end
        process_old_definition(word, definition) if !word.nil?
      end
    end
    
    def run_definition_import(from = nil, to = nil)
      attrs = { task_code: 'dtt-definition-import' }
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
        word = Feature.search_bod_expression(word_str)
        if word.nil?
          word = add_term(definition.id, word_str, definition.wylie, definition.phonetic)
          STDERR.puts "#{Time.now}: Word #{word_str} (#{definition.id}) not found and could not be added." if word.nil?
        end
        process_definition(word, definition) if !word.nil?
      end
    end
    
    def check_old_definitions(from = nil, to = nil)
      definitions = Dictionary::OldDefinition.all.order(:id)
      definitions = definitions.where(['id >= ?', from]) if !from.blank?
      definitions = definitions.where(['id <= ?', to]) if !to.blank?
      definitions.each do |d|
        term = d.term.tibetan_cleanup
        response = addable(term)
        if !response.instance_of? Feature
          if response
            puts "#{term} (#{d.id}) not found but can be added."
          else
            puts "#{term} (#{d.id}) cannot be added."
          end
        end
      end
    end
    
    def check_head_terms(from = nil, to = nil)
      definitions = Dictionary::Definition.where(level: 'head term').order(:id)
      definitions = definitions.where(['id >= ?', from]) if !from.blank?
      definitions = definitions.where(['id <= ?', to]) if !to.blank?
      definitions.each do |definition|
        term_str = definition.term
        next if term_str.blank?
        word_str = term_str.tibetan_cleanup
        response = addable(word_str)
        if !response.instance_of? Feature
          if response
            puts "#{word_str} (#{definition.id}) not found but can be added."
          else
            puts "#{word_str} (#{definition.id}) cannot be added."
          end
        end
      end
    end
    
    private
    
    def process_old_definition(word, source_def)
      source_content = source_def.definition
      source_login = source_def.created_by
      source_person = source_login.blank? ? nil : Dictionary::User.find_by(login: source_login)
      if source_person.nil?
        dest_person = nil
      else
        attrs = { fullname: source_person.full_name }
        dest_person = AuthenticatedSystem::Person.find_by(attrs)
        if dest_person.nil?
          dest_person = AuthenticatedSystem::Person.create!(attrs)
          self.spreadsheet.imports.create!(item: dest_person)
        end
      end
      source_dictionary = source_def.dictionary
      if source_dictionary.blank?
        info_source = nil
      else
        attrs = { title: source_dictionary }
        info_source = InfoSource.find_by(attrs)
        info_source = InfoSource.create!(attrs.merge(code: source_dictionary)) if info_source.nil?
      end
      if source_content.blank?
        dest_def = nil
      else
        lang_code = source_content.language_code
        dest_language = lang_code.blank? ? nil : Language.where(['code like ?', "#{lang_code}%"]).first
        dest_language ||= @default_language
        attrs = { content: source_content }
        definitions = word.definitions
        dest_def = definitions.where(attrs).first
        if dest_def.nil?
          position = definitions.maximum(:position)
          position = position.nil? ? 1 : position + 1
          dest_def = word.definitions.create!(attrs.merge(is_public: true, position: position, language: dest_language, author: dest_person))
          self.spreadsheet.imports.create!(item: dest_def)
          if !info_source.nil?
            citation = dest_def.citations.create!(info_source: info_source)
            self.spreadsheet.imports.create!(item: citation)
          end
          puts "#{Time.now}: Adding #{source_def.id} as root definition for #{word.fid}."
        else
          if !info_source.nil?
            citations = dest_def.citations
            citation = citations.find_by(info_source: info_source)
            if citation.nil?
              citation = citations.create!(info_source: info_source)
              self.spreadsheet.imports.create!(item: citation)
            end
          end
          puts "#{Time.now}: Definition #{source_def.id} already there in #{word.fid}."
        end
      end
    end
    
    def addable(tibetan)
      word = Feature.search_bod_expression(tibetan)
      return word if !word.nil?
      syllable_str = tibetan.split(@intersyllabic_tsheg).first
      syllable = Feature.search_by_phoneme(syllable_str, Feature::BOD_PHRASE_SUBJECT_ID)
      return true if !syllable.nil?
      pos = syllable_str.chars.find_index{|l| l.ord.is_tibetan_vowel?}
      letter_str = nil
      name_str = nil
      if pos.nil?
        if syllable_str.size == 1
          letter_str = syllable_str
          name_str = syllable_str
        # assuming if three letter word with no vowels and stacks, root is middle letter, not taking into account exceptions and secondary suffix for now.
        elsif syllable_str.size == 3 && syllable_str.chars.find_index{|l| !l.ord.is_tibetan_single_letter?}.nil? && syllable_str[0].ord.is_prefix? && syllable_str[2].ord.is_suffix?
          letter_str = syllable_str[1]
          name_str = syllable_str[0...2] + Unicode::U0F60
        else
          name_str = syllable_str if !syllable_str.last.ord.is_suffix?
        end
      else
        pos +=1 if p==0
        name_str = syllable_str[0...pos]
      end
      if name_str.blank? # Grammatical name cannot be easily identified.
        STDERR.puts "#{Time.now}: Grammatical name cannot be easily identified."
        return false
      end
      name = Feature.search_by_phoneme(name_str, Feature::BOD_NAME_SUBJECT_ID)
      return true if !name.nil?

      letter_str = name_str.tibetan_base_letter if letter_str.nil?
      if letter_str.blank? # Grammatical name not found and root letter cannot be identified.
        STDERR.puts "#{Time.now}: Grammatical name not found and root letter cannot be identified."
        return false
      end
      letter = Feature.search_by_phoneme(letter_str, Feature::BOD_LETTER_SUBJECT_ID)
      if letter.nil? # Not confortable adding a new letter!
        STDERR.puts "#{Time.now}: Not confortable adding a new letter."
        return false
      end
      return true
    end
    
    def add_term(old_pid, tibetan = nil, wylie = nil, phonetic = nil)
      word = Feature.search_bod_expression(tibetan)
      return word if !word.nil?
      syllable_str = tibetan.split(@intersyllabic_tsheg).first
      syllable = Feature.search_by_phoneme(syllable_str, Feature::BOD_PHRASE_SUBJECT_ID)
      if !syllable.nil?
        word = process_term(old_pid, nil, Feature::BOD_EXPRESSION_SUBJECT_ID, tibetan, wylie, phonetic)
        relation = FeatureRelation.create!(child_node: word, parent_node: syllable, perspective: @tib_alpha, feature_relation_type: @relation_type)
        self.spreadsheet.imports.create!(item: relation)
        syllable.queued_index(priority: Flare::IndexerJob::LOW)
        word.queued_index(priority: Flare::IndexerJob::LOW)
        return word
      end
      pos = syllable_str.chars.find_index{|l| l.ord.is_tibetan_vowel?}
      letter_str = nil
      name_str = nil
      if pos.nil?
        if syllable_str.size == 1
          letter_str = syllable_str
          name_str = syllable_str
          # assuming if three letter word with no vowels and stacks, root is middle letter, not taking into account exceptions and secondary suffix for now.
        elsif syllable_str.size == 3 && syllable_str.chars.find_index{|l| !l.ord.is_tibetan_single_letter?}.nil? && syllable_str[0].ord.is_prefix? && syllable_str[2].ord.is_suffix?
          letter_str = syllable_str[1]
          name_str = syllable_str[0...2] + Unicode::U0F60
        else
          name_str = syllable_str if !syllable_str.last.ord.is_suffix?
        end
      else
        pos +=1 if p==0
        name_str = syllable_str[0...pos]
      end
      return nil if name_str.blank? # Grammatical name cannot be easily identified."
      name = Feature.search_by_phoneme(name_str, Feature::BOD_NAME_SUBJECT_ID)
      if !name.nil?
        syllable = process_term(old_pid, nil, Feature::BOD_PHRASE_SUBJECT_ID, syllable_str)
        relation = FeatureRelation.create!(child_node: syllable, parent_node: name, perspective: @tib_alpha, feature_relation_type: @relation_type)
        self.spreadsheet.imports.create!(item: relation)
        word = process_term(old_pid, nil, Feature::BOD_EXPRESSION_SUBJECT_ID, tibetan, wylie, phonetic)
        relation = FeatureRelation.create!(child_node: word, parent_node: syllable, perspective: @tib_alpha, feature_relation_type: @relation_type)
        self.spreadsheet.imports.create!(item: relation)
        name.queued_index(priority: Flare::IndexerJob::LOW)
        syllable.queued_index(priority: Flare::IndexerJob::LOW)
        word.queued_index(priority: Flare::IndexerJob::LOW)
        return word
      end
      letter_str = name_str.tibetan_base_letter if letter_str.nil?
      return nil if letter_str.blank? # Grammatical name not found and root letter cannot be identified.
      letter = Feature.search_by_phoneme(letter_str, Feature::BOD_LETTER_SUBJECT_ID)
      return nil if letter.nil? # Not confortable adding a new letter!
      name = process_term(old_pid, nil, Feature::BOD_NAME_SUBJECT_ID, name_str)
      relation = FeatureRelation.create!(child_node: name, parent_node: letter, perspective: @tib_alpha, feature_relation_type: @relation_type)
      self.spreadsheet.imports.create!(item: relation)
      syllable = process_term(old_pid, nil, Feature::BOD_PHRASE_SUBJECT_ID, syllable_str)
      relation = FeatureRelation.create!(child_node: syllable, parent_node: name, perspective: @tib_alpha, feature_relation_type: @relation_type)
      self.spreadsheet.imports.create!(item: relation)
      word = process_term(old_pid, nil, Feature::BOD_EXPRESSION_SUBJECT_ID, tibetan, wylie, phonetic)
      relation = FeatureRelation.create!(child_node: word, parent_node: syllable, perspective: @tib_alpha, feature_relation_type: @relation_type)
      self.spreadsheet.imports.create!(item: relation)
      letter.queued_index(priority: Flare::IndexerJob::LOW)
      name.queued_index(priority: Flare::IndexerJob::LOW)
      syllable.queued_index(priority: Flare::IndexerJob::LOW)
      word.queued_index(priority: Flare::IndexerJob::LOW)
      return word
    end
  end
end