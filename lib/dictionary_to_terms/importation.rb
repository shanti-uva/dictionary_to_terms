module DictionaryToTerms
  class Importation
    attr_accessor :spreadsheet
    
    def initialize
      @tib_alpha = Perspective.get_by_code('tib.alpha')
      @relation_type = FeatureRelationType.get_by_code('is.beginning.of')
      @space = Unicode::U0F0B
      @zero_width_space = Unicode::UFEFF
      @nb_space = Unicode::U00A0
      
      
      @tibetan_script = WritingSystem.get_by_code('tibt')
      @tibetan_language = Language.get_by_code('bod')
      @latin_script = WritingSystem.get_by_code('latin')
      @wylie_system = OrthographicSystem.get_by_code('thl.ext.wyl.translit')
      @thl_phonetic = PhoneticSystem.get_by_code('thl.simple.transcrip')
    end
    
    def run_importation
      puts "#{Time.now}: Starting importation."
      task = ImportationTask.find_by(task_code: 'dictionary-to-terms-import')
      task = ImportationTask.create!(task_code: 'dictionary-to-terms-import') if task.nil?
      self.spreadsheet = task.spreadsheets.find_by(filename: DictionaryToTerms.dictionary_database_yaml['database'])
      self.spreadsheet = task.spreadsheets.create!(filename: DictionaryToTerms.dictionary_database_yaml['database'], imported_at: Time.now) if self.spreadsheet.nil?
      i = 1
      ComplexScripts::TibetanLetter.all.each do |letter|
        root = process_term(nil, i, letter.unicode, "#{letter.wylie}a")
        puts "#{Time.now}: Letter #{letter.wylie}a processed as #{root.pid}."
        i+=1
        sid = Spawnling.new do
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
            if prefixes[prefix].nil?
              tibetan_syllable = definition.term.split(@space).first
              prefix_term = process_term(nil, j, tibetan_syllable, prefix)
              prefixes[prefix] = prefix_term
              relation = FeatureRelation.create!(skip_update: true, child_node: prefix_term, parent_node: root, perspective: @tib_alpha, feature_relation_type: @relation_type)
              self.spreadsheet.imports.create!(item: relation)
              puts "#{Time.now}: Term #{prefix} processed as #{prefix_term.pid}."
              j += 1
              prefix_position[prefix] = 1
            end
            syllable = wylie.gsub(@nb_space, ' ').split(' ').first.gsub(@zero_width_space, '').gsub('/', '')
            if syllables[syllable].nil?
              tibetan_syllable = definition.term.split(@space).first
              syllable_term = process_term(nil, prefix_position[prefix], tibetan_syllable, syllable)
              prefix_position[prefix] += 1
              syllables[syllable] = syllable_term
              relation = FeatureRelation.create!(skip_update: true, child_node: syllable_term, parent_node: prefixes[prefix], perspective: @tib_alpha, feature_relation_type: @relation_type)
              self.spreadsheet.imports.create!(item: relation)
              puts "#{Time.now}: Syllable #{syllable} processed as #{syllable_term.pid}."
              syllable_position[syllable] = 1
            end
            word = process_term(definition.id, syllable_position[syllable], definition.term, definition.wylie, definition.phonetic)
            syllable_position[syllable] += 1
            relation = FeatureRelation.create!(skip_update: true, child_node: word, parent_node: syllables[syllable], perspective: @tib_alpha, feature_relation_type: @relation_type)
            self.spreadsheet.imports.create!(item: relation)
            puts "#{Time.now}: Word #{definition.wylie} processed as #{word.pid}."
          end
        end
        Spawnling.wait([sid])
        KmapsEngine::FeaturePidGenerator.configure
      end
      process_triggers
    end
    
    def process_term(old_pid, position, tibetan = nil, wylie = nil, phonetic = nil)
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
      return f
    end
    
    def process_triggers
      Feature.all.each do |f|
        sid = Spawnling.new do
          puts "Spawning sub-process #{Process.pid}."
          f.update_hierarchy
          f.update_cached_feature_names
          f.update_name_positions
          f.names.first.ensure_one_primary
          puts "#{Time.now}: Triggers updated for #{f.pid}."
        end
        Spawnling.wait([sid])
      end
    end
  end
end
