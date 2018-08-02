module DictionaryToTerms
  class TreeProcessing
    attr_accessor :spreadsheet
    
    def initialize
      @tib_alpha = Perspective.get_by_code('tib.alpha')
      @tibetan_script = WritingSystem.get_by_code('tibt')
      @tibetan_language = Language.get_by_code('bod')
      @latin_script = WritingSystem.get_by_code('latin')
      @wylie_system = OrthographicSystem.get_by_code('thl.ext.wyl.translit')
      @thl_phonetic = PhoneticSystem.get_by_code('thl.simple.transcrip')

      @intersyllabic_tsheg = Unicode::U0F0B
      
      @zero_width_space = Unicode::UFEFF
      @nb_space = Unicode::U00A0
      
      @default_language = Language.get_by_code('eng')
      @relation_type = FeatureRelationType.get_by_code('is.beginning.of')
    end
    
    def run_tree_importation
      puts "#{Time.now}: Starting importation."
      task = ImportationTask.find_by(task_code: 'dtt-tree-import')
      task = ImportationTask.create!(task_code: 'dtt-tree-import') if task.nil?
      self.spreadsheet = task.spreadsheets.find_by(filename: DictionaryToTerms.dictionary_database_yaml['database'])
      self.spreadsheet = task.spreadsheets.create!(filename: DictionaryToTerms.dictionary_database_yaml['database'], imported_at: Time.now) if self.spreadsheet.nil?
      i = 1
      ComplexScripts::TibetanLetter.all.each do |letter|
        root = process_term(nil, i, Feature::LETTER_SUBJECT_ID, letter.unicode, "#{letter.wylie}a")
        puts "#{Time.now}: Letter #{letter.wylie}a processed as #{root.pid}."
        i+=1
        sid = Spawnling.new do
          begin
            puts "Spawning sub-process #{Process.pid}."
            j = 1
            syllables = {}
            prefixes = {}
            prefix_position = {}
            syllable_position = {}
            Dictionary::Definition.where(root_letter_id: letter.id, level: 'head term').order(:sort_order).each do |definition|
              wylie = definition.wylie
              next if wylie.blank?
              prefix = wylie.prefixed_letters('bod')
              next if prefix.blank?
              term = definition.term.tibetan_cleanup
              if prefixes[prefix].nil?
                tibetan_syllable = term.split(@intersyllabic_tsheg).first
                prefix_term = process_term(nil, j, Feature::NAME_SUBJECT_ID, tibetan_syllable, prefix)
                prefixes[prefix] = prefix_term
                relation = FeatureRelation.create!(skip_update: true, child_node: prefix_term, parent_node: root, perspective: @tib_alpha, feature_relation_type: @relation_type)
                self.spreadsheet.imports.create!(item: relation)
                puts "#{Time.now}: Term #{prefix} processed as #{prefix_term.pid}."
                j += 1
                prefix_position[prefix] = 1
              end
              syllable = wylie.gsub(@nb_space, ' ').split(' ').first.gsub(@zero_width_space, '').gsub('/', '')
              if syllables[syllable].nil?
                tibetan_syllable = term.split(@intersyllabic_tsheg).first
                syllable_term = process_term(nil, prefix_position[prefix], Feature::PHRASE_SUBJECT_ID, tibetan_syllable, syllable)
                prefix_position[prefix] += 1
                syllables[syllable] = syllable_term
                relation = FeatureRelation.create!(skip_update: true, child_node: syllable_term, parent_node: prefixes[prefix], perspective: @tib_alpha, feature_relation_type: @relation_type)
                self.spreadsheet.imports.create!(item: relation)
                puts "#{Time.now}: Syllable #{syllable} processed as #{syllable_term.pid}."
                syllable_position[syllable] = 1
              end
              word = Feature.search_expression(term)
              if word.nil?
                word = process_term(definition.id, syllable_position[syllable], Feature::EXPRESSION_SUBJECT_ID, term, definition.wylie, definition.phonetic)
                syllable_position[syllable] += 1
                relation = FeatureRelation.create!(skip_update: true, child_node: word, parent_node: syllables[syllable], perspective: @tib_alpha, feature_relation_type: @relation_type)
                self.spreadsheet.imports.create!(item: relation)
                puts "#{Time.now}: Word #{definition.wylie} processed as #{word.pid}."
              end
            end
          rescue Exception => e
            STDERR.puts e.to_s
          end
        end
        Spawnling.wait([sid])
        KmapsEngine::FeaturePidGenerator.configure
      end
      process_triggers
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
        sid = Spawnling.new do
          begin
            puts "Spawning sub-process #{Process.pid} for processing definition #{definition.id}"
            word_str = term_str.tibetan_cleanup
            word = Feature.search_expression(word_str)
            if word.nil?
              word = add_term(definition.id, word_str)
              STDERR.puts "#{Time.now}: Word #{word_str} (#{definition.id}) not found and could not be added." if word.nil?
            end
            process_old_definition(word, definition) if !word.nil?
          rescue Exception => e
            STDERR.puts e.to_s
          end
        end
        Spawnling.wait([sid])
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
        sid = Spawnling.new do
          begin
            puts "Spawning sub-process #{Process.pid} for processing definition #{definition.id}"
            word_str = term_str.tibetan_cleanup
            word = Feature.search_expression(word_str)
            if word.nil?
              word = add_term(definition.id, word_str, definition.wylie, definition.phonetic)
              STDERR.puts "#{Time.now}: Word #{word_str} (#{definition.id}) not found and could not be added." if word.nil?
            end
            process_definition(word, definition) if !word.nil?
          rescue Exception => e
            STDERR.puts e.to_s
          end
        end
        Spawnling.wait([sid])
      end
    end
    
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
            process_subjects(definition, word.subject_term_associations, word.definitions)
          rescue Exception => e
            STDERR.puts e.to_s
          end
        end
        Spawnling.wait([sid])
      end
    end
    
    def run_tree_classification
      roman = View.get_by_code('roman.popular')
      Feature.current_roots(@tib_alpha, roman).each do |letter_term|
        if letter_term.subject_term_associations.empty?
          a = letter_term.subject_term_associations.create!(subject_id: Feature::LETTER_SUBJECT_ID, branch_id: Feature::PHONEME_SUBJECT_ID)
          puts "#{Time.now}: #{letter_term.prioritized_name(roman).name} #{letter_term.pid} marked as letter." if !a.nil?
        end
        letter_term.current_children(@tib_alpha, roman).each do |name_term|
          if name_term.subject_term_associations.empty?
            a = name_term.subject_term_associations.create!(subject_id: Feature::NAME_SUBJECT_ID, branch_id: Feature::PHONEME_SUBJECT_ID)
            puts "#{Time.now}: #{name_term.prioritized_name(roman).name} #{name_term.pid} marked as name." if !a.nil?
          end
          sid = Spawnling.new do
            begin
              puts "Spawning sub-process #{Process.pid}."
              name_term.current_children(@tib_alpha, roman).each do |phrase_term|
                if phrase_term.subject_term_associations.empty?
                  a = phrase_term.subject_term_associations.create!(subject_id: Feature::PHRASE_SUBJECT_ID, branch_id: Feature::PHONEME_SUBJECT_ID)
                  puts "#{Time.now}: #{phrase_term.prioritized_name(roman).name} #{phrase_term.pid} marked as phrase." if !a.nil?
                end
                phrase_term.current_children(@tib_alpha, roman).each do |expression_term|
                  if expression_term.subject_term_associations.empty?
                    a = expression_term.subject_term_associations.create!(subject_id: Feature::EXPRESSION_SUBJECT_ID, branch_id: Feature::PHONEME_SUBJECT_ID)
                    puts "#{Time.now}: #{expression_term.prioritized_name(roman).name} #{expression_term.pid} marked as expression." if !a.nil?
                  end
                end
              end
            rescue Exception => e
              STDERR.puts e.to_s
            end
          end
          Spawnling.wait([sid])
        end
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
    
    def run_tree_flattening_into_third_level
      v = View.get_by_code('roman.scholar')
      Feature.roots.order(:position).collect do |letter|
        expression_number = Feature.search_by("ancestor_ids_tib.alpha:#{letter.fid} AND associated_subject_#{Feature::PHONEME_SUBJECT_ID}_ls:#{Feature::EXPRESSION_SUBJECT_ID}")['numFound']
        root = Math.sqrt(expression_number).floor
        name_terms = letter.children
        puts "#{Time.now}: Processing letter #{letter.prioritized_name(v).name}..."
        for name_term in name_terms
          sid = Spawnling.new do
            begin
              puts "#{Time.now}: Spawning sub-process #{Process.pid} for the collapse of #{name_term.prioritized_name(v).name} (T#{name_term.fid})."
              expression_number = Feature.search_by("ancestor_ids_tib.alpha:#{name_term.fid} AND associated_subject_#{Feature::PHONEME_SUBJECT_ID}_ls:#{Feature::EXPRESSION_SUBJECT_ID}")['numFound']
              phrase_relations = name_term.child_relations
              if expression_number <= root || phrase_relations.size==1
                for phrase_relation in phrase_relations
                  phrase = phrase_relation.child_node
                  expression_relations = phrase.child_relations
                  for expression_relation in expression_relations
                    expression = expression_relation.child_node
                    puts "#{Time.now}: Moving expression #{expression.prioritized_name(v).name} (T#{expression.fid})."
                    expression_relation.update_attribute(:parent_node_id, name_term.id)
                    expression.index!
                  end
                  puts "#{Time.now}: Deleting phrase #{phrase.prioritized_name(v).name} (T#{phrase.fid})."
                  expression_relations.reload
                  phrase_relation.destroy
                  phrase.remove!
                  phrase.destroy
                end
                puts "#{Time.now}: Reindexing name #{name_term.prioritized_name(v).name} (T#{name_term.fid})"
                phrase_relations.reload
                name_term.index!
              else
                for phrase_relation in phrase_relations
                  phrase = phrase_relation.child_node
                  puts "#{Time.now}: Moving phrase #{phrase.prioritized_name(v).name} (T#{phrase.fid})."
                  phrase_relation.update_attribute(:parent_node_id, letter.id)
                  phrase.index!
                  phrase.children.each do |expression|
                    puts "#{Time.now}: Reindexing expression #{expression.prioritized_name(v).name} (T#{expression.fid})."
                    expression.index!
                  end
                end
                puts "#{Time.now}: Deleting name #{name_term.prioritized_name(v).name} (T#{name_term.fid})."
                phrase_relations.reload
                name_term.remove!
                name_term.destroy
              end
              puts "#{Time.now}: Finishing sub-process #{Process.pid}."
            rescue Exception => e
              STDERR.puts e.to_s
            end
          end
          Spawnling.wait([sid])
        end
        name_terms.reload
        letter.index!
      end
      Flare.commit
    end
    
    private
    
    def process_term(old_pid, position, level_subject_id, tibetan = nil, wylie = nil, phonetic = nil)
      f = Feature.create!(fid: Feature.generate_pid, old_pid: old_pid, position: position, is_public: 1)
      self.spreadsheet.imports.create!(item: f)
      names = f.names
      if tibetan.blank?
        tibetan_name = nil
      else
        tibetan_name = names.create!(skip_update: true, name: tibetan, position: 0, writing_system: @tibetan_script, language: @tibetan_language, is_primary_for_romanization: false)
        self.spreadsheet.imports.create!(item: tibetan_name)
      end
      if wylie.blank?
        wylie_name = nil
      else
        wylie_name = names.create!(skip_update: true, name: wylie, position: 1, writing_system: @latin_script, language: @tibetan_language, is_primary_for_romanization: true)
        self.spreadsheet.imports.create!(item: wylie_name)
        if !tibetan_name.nil?
          relation = FeatureNameRelation.create!(skip_update: true, parent_node: tibetan_name, child_node: wylie_name, is_phonetic: 0, is_orthographic: 1, is_translation: 0, is_alt_spelling: 0, orthographic_system: @wylie_system)
          self.spreadsheet.imports.create!(item: relation)
        end
      end
      if !phonetic.blank?
        phonetic_name = names.create!(skip_update: true, name: phonetic, position: 2, writing_system: @latin_script, language: @tibetan_language, is_primary_for_romanization: false)
        if !tibetan_name.blank? || !wylie_name.blank?
          relation = FeatureNameRelation.create!(skip_update: true, parent_node: tibetan_name || wylie_name, child_node: phonetic_name, is_phonetic: 1, is_orthographic: 0, is_translation: 0, is_alt_spelling: 0, phonetic_system: @thl_phonetic)
          self.spreadsheet.imports.create!(item: relation)
        end
      end
      if f.subject_term_associations.empty?
        a = f.subject_term_associations.create(subject_id: level_subject_id, branch_id: Feature::PHONEME_SUBJECT_ID)
        self.spreadsheet.imports.create!(item: a)
      end
      return f
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
    
    def process_subjects(source_def, subject_associations, dest_defs)
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
        process_subjects(child, dest_def.definition_subject_associations, dest_def.children)
      end
    end
    
    def process_definition(word, source_def, parent_def = nil, position = 1)
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
      if source_content.blank?
        dest_def = nil
      else
        source_language = source_def.language
        if source_language.blank?
          lang_code = source_content.language_code
          dest_language = lang_code.blank? ? nil : Language.where(['code like ?', "#{lang_code}%"]).first
          dest_language ||= @default_language
        else
          dest_language = Language.get_by_name(source_language)
        end
        attrs = { content: source_content }
        dest_def = word.definitions.where(attrs).first
        if dest_def.nil?
          dest_def = word.definitions.create!(attrs.merge(is_public: true, position: position, language: dest_language, author: dest_person, numerology: source_def.numerology, tense: source_def.tense))
          self.spreadsheet.imports.create!(item: dest_def)
          puts "#{Time.now}: Adding #{source_def.id} as #{parent_def.nil? ? 'root' : 'child'} definition for #{word.fid}."
          
          # only want to establish relationship if definition is new
          if !parent_def.nil?
            attrs = { parent_node: parent_def, child_node: dest_def }
            relation = DefinitionRelation.where(attrs).first
            if relation.nil?
              relation = DefinitionRelation.create!(attrs)
              self.spreadsheet.imports.create!(item: relation)
            end
          end
        end
        source_note = source_def.analytical_note
        if !source_note.blank?
          attrs = { content: source_note }
          dest_note = dest_def.notes.where(attrs).first
          if dest_note.nil?
            dest_note = dest_def.notes.create!(attrs)
            self.spreadsheet.imports.create!(item: dest_note)
          end
          dest_note.authors << dest_person if !dest_person.nil? && dest_note.authors.where(id: dest_person).first.nil?
        end
      end
      children = source_def.super_definitions.collect{|s| s.sub_definition}.reject(&:nil?)
      child_position = 1
      children.each do |child|
        process_definition(word, child, dest_def, child_position)
        child_position += 1
      end
    end
    
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
      word = Feature.search_expression(tibetan)
      return word if !word.nil?
      syllable_str = tibetan.split(@intersyllabic_tsheg).first
      syllable = Feature.search_by_phoneme(syllable_str, Feature::PHRASE_SUBJECT_ID)
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
      name = Feature.search_by_phoneme(name_str, Feature::NAME_SUBJECT_ID)
      return true if !name.nil?

      letter_str = name_str.tibetan_base_letter if letter_str.nil?
      if letter_str.blank? # Grammatical name not found and root letter cannot be identified.
        STDERR.puts "#{Time.now}: Grammatical name not found and root letter cannot be identified."
        return false
      end
      letter = Feature.search_by_phoneme(letter_str, Feature::LETTER_SUBJECT_ID)
      if letter.nil? # Not confortable adding a new letter!
        STDERR.puts "#{Time.now}: Not confortable adding a new letter."
        return false
      end
      return true
    end
    
    def add_term(old_pid, tibetan = nil, wylie = nil, phonetic = nil)
      word = Feature.search_expression(tibetan)
      return word if !word.nil?
      syllable_str = tibetan.split(@intersyllabic_tsheg).first
      syllable = Feature.search_by_phoneme(syllable_str, Feature::PHRASE_SUBJECT_ID)
      if !syllable.nil?
        word = process_term(old_pid, nil, Feature::EXPRESSION_SUBJECT_ID, tibetan, wylie, phonetic)
        relation = FeatureRelation.create!(child_node: word, parent_node: syllable, perspective: @tib_alpha, feature_relation_type: @relation_type)
        self.spreadsheet.imports.create!(item: relation)
        syllable.index!
        word.index!
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
      name = Feature.search_by_phoneme(name_str, Feature::NAME_SUBJECT_ID)
      if !name.nil?
        syllable = process_term(old_pid, nil, Feature::PHRASE_SUBJECT_ID, syllable_str)
        relation = FeatureRelation.create!(child_node: syllable, parent_node: name, perspective: @tib_alpha, feature_relation_type: @relation_type)
        self.spreadsheet.imports.create!(item: relation)
        word = process_term(old_pid, nil, Feature::EXPRESSION_SUBJECT_ID, tibetan, wylie, phonetic)
        relation = FeatureRelation.create!(child_node: word, parent_node: syllable, perspective: @tib_alpha, feature_relation_type: @relation_type)
        self.spreadsheet.imports.create!(item: relation)
        name.index!
        syllable.index!
        word.index!
        return word
      end
      letter_str = name_str.tibetan_base_letter if letter_str.nil?
      return nil if letter_str.blank? # Grammatical name not found and root letter cannot be identified.
      letter = Feature.search_by_phoneme(letter_str, Feature::LETTER_SUBJECT_ID)
      return nil if letter.nil? # Not confortable adding a new letter!
      name = process_term(old_pid, nil, Feature::NAME_SUBJECT_ID, name_str)
      relation = FeatureRelation.create!(child_node: name, parent_node: letter, perspective: @tib_alpha, feature_relation_type: @relation_type)
      self.spreadsheet.imports.create!(item: relation)
      syllable = process_term(old_pid, nil, Feature::PHRASE_SUBJECT_ID, syllable_str)
      relation = FeatureRelation.create!(child_node: syllable, parent_node: name, perspective: @tib_alpha, feature_relation_type: @relation_type)
      self.spreadsheet.imports.create!(item: relation)
      word = process_term(old_pid, nil, Feature::EXPRESSION_SUBJECT_ID, tibetan, wylie, phonetic)
      relation = FeatureRelation.create!(child_node: word, parent_node: syllable, perspective: @tib_alpha, feature_relation_type: @relation_type)
      self.spreadsheet.imports.create!(item: relation)
      letter.index!
      name.index!
      syllable.index!
      word.index!
      return word
    end
    
    def process_triggers
      Feature.all.each do |f|
        sid = Spawnling.new do
          begin
            puts "Spawning sub-process #{Process.pid}."
            f.update_hierarchy
            f.update_cached_feature_names
            f.update_name_positions
            f.names.first.ensure_one_primary
            puts "#{Time.now}: Triggers updated for #{f.pid}."
          rescue Exception => e
            STDERR.puts e.to_s
          end
        end
        Spawnling.wait([sid])
      end
    end
  end
end