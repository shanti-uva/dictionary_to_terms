module DictionaryToTerms
  class TreeProcessing
    attr_accessor :spreadsheet
    
    def initialize
      @intersyllabic_tsheg = Unicode::U0F0B
      @tib_alpha = Perspective.get_by_code('tib.alpha')
      @relation_type = FeatureRelationType.get_by_code('is.beginning.of')
      @nb_space = Unicode::U00A0
      @zero_width_space = Unicode::UFEFF
      @fixed_size = 100
      @tibetan_script = WritingSystem.get_by_code('tibt')
      @latin_script = WritingSystem.get_by_code('latin')
      @wylie_system = OrthographicSystem.get_by_code('thl.ext.wyl.translit')
      @thl_phonetic = PhoneticSystem.get_by_code('thl.simple.transcrip')
      @tibetan_language = Language.get_by_code('bod')
    end
    
    def run_tree_importation
      puts "#{Time.now}: Starting importation."
      task = ImportationTask.find_by(task_code: 'dtt-tree-import')
      task = ImportationTask.create!(task_code: 'dtt-tree-import') if task.nil?
      self.spreadsheet = task.spreadsheets.find_by(filename: DictionaryToTerms.dictionary_database_yaml['database'])
      self.spreadsheet = task.spreadsheets.create!(filename: DictionaryToTerms.dictionary_database_yaml['database'], imported_at: Time.now) if self.spreadsheet.nil?
      i = 1
      ComplexScripts::TibetanLetter.all.each do |letter|
        root = process_term(nil, i, Feature::BOD_LETTER_SUBJECT_ID, letter.unicode, "#{letter.wylie}a")
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
                prefix_term = process_term(nil, j, Feature::BOD_NAME_SUBJECT_ID, tibetan_syllable, prefix)
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
                syllable_term = process_term(nil, prefix_position[prefix], Feature::BOD_PHRASE_SUBJECT_ID, tibetan_syllable, syllable)
                prefix_position[prefix] += 1
                syllables[syllable] = syllable_term
                relation = FeatureRelation.create!(skip_update: true, child_node: syllable_term, parent_node: prefixes[prefix], perspective: @tib_alpha, feature_relation_type: @relation_type)
                self.spreadsheet.imports.create!(item: relation)
                puts "#{Time.now}: Syllable #{syllable} processed as #{syllable_term.pid}."
                syllable_position[syllable] = 1
              end
              word = Feature.search_bod_expression(term)
              if word.nil?
                word = process_term(definition.id, syllable_position[syllable], Feature::BOD_EXPRESSION_SUBJECT_ID, term, definition.wylie, definition.phonetic)
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
    
    def run_tree_classification
      roman = View.get_by_code('roman.popular')
      Feature.current_roots(@tib_alpha, roman).each do |letter_term|
        if letter_term.subject_term_associations.empty?
          a = letter_term.subject_term_associations.create!(subject_id: Feature::BOD_LETTER_SUBJECT_ID, branch_id: Feature::BOD_PHONEME_SUBJECT_ID)
          puts "#{Time.now}: #{letter_term.prioritized_name(roman).name} #{letter_term.pid} marked as letter." if !a.nil?
        end
        letter_term.current_children(@tib_alpha, roman).each do |name_term|
          if name_term.subject_term_associations.empty?
            a = name_term.subject_term_associations.create!(subject_id: Feature::BOD_NAME_SUBJECT_ID, branch_id: Feature::BOD_PHONEME_SUBJECT_ID)
            puts "#{Time.now}: #{name_term.prioritized_name(roman).name} #{name_term.pid} marked as name." if !a.nil?
          end
          sid = Spawnling.new do
            begin
              puts "Spawning sub-process #{Process.pid}."
              name_term.current_children(@tib_alpha, roman).each do |phrase_term|
                if phrase_term.subject_term_associations.empty?
                  a = phrase_term.subject_term_associations.create!(subject_id: Feature::BOD_PHRASE_SUBJECT_ID, branch_id: Feature::BOD_PHONEME_SUBJECT_ID)
                  puts "#{Time.now}: #{phrase_term.prioritized_name(roman).name} #{phrase_term.pid} marked as phrase." if !a.nil?
                end
                phrase_term.current_children(@tib_alpha, roman).each do |expression_term|
                  if expression_term.subject_term_associations.empty?
                    a = expression_term.subject_term_associations.create!(subject_id: Feature::BOD_EXPRESSION_SUBJECT_ID, branch_id: Feature::BOD_PHONEME_SUBJECT_ID)
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
    
    def run_tree_flattening_into_second_level
      v = View.get_by_code('roman.scholar')
      Feature.roots.order(:position).collect do |letter|
        name_terms = letter.children.select{|n| n.phoneme_term_associations.first.subject_id == Feature::BOD_NAME_SUBJECT_ID}
        puts "#{Time.now}: Processing letter #{letter.prioritized_name(v).name}..."
        for name_term in name_terms
          phrase_relations = name_term.child_relations
          sid = Spawnling.new do
            begin
              puts "#{Time.now}: Spawning sub-process #{Process.pid} for the collapse of #{name_term.prioritized_name(v).name} (T#{name_term.fid})."
              some_phrase_processed = false
              for phrase_relation in phrase_relations
                phrase = phrase_relation.child_node
                next if phrase.phoneme_term_associations.first.subject_id != Feature::BOD_PHRASE_SUBJECT_ID
                some_phrase_processed = true
                expression_relations = phrase.child_relations
                for expression_relation in expression_relations
                  expression = expression_relation.child_node
                  next if expression.phoneme_term_associations.first.subject_id != Feature::BOD_EXPRESSION_SUBJECT_ID
                  puts "#{Time.now}: Moving expression #{expression.prioritized_name(v).name} (T#{expression.fid})."
                  expression_relation.update_attribute(:parent_node_id, name_term.id)
                  expression.index!
                end
                puts "#{Time.now}: Deleting phrase #{phrase.prioritized_name(v).name} (T#{phrase.fid})."
                phrase.child_relations.reload
                phrase_relation.destroy
                phrase.remove!
                phrase.destroy
              end
              if some_phrase_processed
                puts "#{Time.now}: Reindexing name #{name_term.prioritized_name(v).name} (T#{name_term.fid})"
                name_term.child_relations.reload
                name_term.index!
              end
              puts "#{Time.now}: Finishing sub-process #{Process.pid}."
            rescue Exception => e
              STDERR.puts e.to_s
            end
          end
          Spawnling.wait([sid])
        end
      end
      Flare.commit
    end
    
    def run_tree_flattening_into_third_level
      v = View.get_by_code('roman.scholar')
      Feature.roots.order(:position).collect do |letter|
        expression_number = Feature.search_by("ancestor_ids_tib.alpha:#{letter.fid} AND associated_subject_#{Feature::BOD_PHONEME_SUBJECT_ID}_ls:#{Feature::BOD_EXPRESSION_SUBJECT_ID}")['numFound']
        root = Math.sqrt(expression_number).floor
        name_terms = letter.children.select{|n| n.phoneme_term_associations.first.subject_id == Feature::BOD_NAME_SUBJECT_ID}
        puts "#{Time.now}: Processing letter #{letter.prioritized_name(v).name}..."
        for name_term in name_terms
          sid = Spawnling.new do
            begin
              puts "#{Time.now}: Spawning sub-process #{Process.pid} for the collapse of #{name_term.prioritized_name(v).name} (T#{name_term.fid})."
              expression_number = Feature.search_by("ancestor_ids_tib.alpha:#{name_term.fid} AND associated_subject_#{Feature::BOD_PHONEME_SUBJECT_ID}_ls:#{Feature::BOD_EXPRESSION_SUBJECT_ID}")['numFound']
              phrase_relations = name_term.child_relations
              if expression_number <= root || phrase_relations.size==1
                some_phrase_processed = false
                for phrase_relation in phrase_relations
                  phrase = phrase_relation.child_node
                  next if phrase.phoneme_term_associations.first.subject_id != Feature::BOD_PHRASE_SUBJECT_ID
                  expression_relations = phrase.child_relations
                  for expression_relation in expression_relations
                    expression = expression_relation.child_node
                    next if expression.phoneme_term_associations.first.subject_id != Feature::BOD_EXPRESSION_SUBJECT_ID
                    puts "#{Time.now}: Moving expression #{expression.prioritized_name(v).name} (T#{expression.fid})."
                    expression_relation.update_attribute(:parent_node_id, name_term.id)
                    expression.index!
                  end
                  puts "#{Time.now}: Deleting phrase #{phrase.prioritized_name(v).name} (T#{phrase.fid})."
                  expression_relations.reload
                  phrase_relation.destroy
                  phrase.remove!
                  phrase.destroy
                  some_phrase_processed = true
                end
                if some_phrase_processed
                  puts "#{Time.now}: Reindexing name #{name_term.prioritized_name(v).name} (T#{name_term.fid})"
                  phrase_relations.reload
                  name_term.index!
                end
              else
                for phrase_relation in phrase_relations
                  phrase = phrase_relation.child_node
                  next if phrase.phoneme_term_associations.first.subject_id != Feature::BOD_PHRASE_SUBJECT_ID
                  puts "#{Time.now}: Moving phrase #{phrase.prioritized_name(v).name} (T#{phrase.fid})."
                  phrase_relation.update_attribute(:parent_node_id, letter.id)
                  phrase.index!
                  phrase.children.each do |expression|
                    next if expression.phoneme_term_associations.first.subject_id != Feature::BOD_EXPRESSION_SUBJECT_ID
                    puts "#{Time.now}: Reindexing expression #{expression.prioritized_name(v).name} (T#{expression.fid})."
                    expression.index!
                  end
                end
                puts "#{Time.now}: Deleting name #{name_term.prioritized_name(v).name} (T#{name_term.fid})."
                phrase_relations.reload
                if phrase_relations.size==0 # should always be the case, unless expressions already moved here
                  name_term.remove!
                  name_term.destroy
                end
              end
              puts "#{Time.now}: Finishing sub-process #{Process.pid}."
            rescue Exception => e
              STDERR.puts e.to_s
            end
          end
          Spawnling.wait([sid])
        end
        letter.children.reload
        letter.index!
      end
      Flare.commit
    end
    
    def run_tree_flattening_mixed
      v = View.get_by_code('roman.scholar')
      Feature.roots.order(:position).collect do |letter|
        expression_number = Feature.search_by("ancestor_ids_tib.alpha:#{letter.fid} AND associated_subject_#{Feature::BOD_PHONEME_SUBJECT_ID}_ls:#{Feature::BOD_EXPRESSION_SUBJECT_ID}")['numFound']
        root = Math.sqrt(expression_number).floor
        name_terms = letter.children
        puts "#{Time.now}: Processing letter #{letter.prioritized_name(v).name}..."
        for name_term in name_terms
          expression_number = Feature.search_by("ancestor_ids_tib.alpha:#{name_term.fid} AND associated_subject_#{Feature::BOD_PHONEME_SUBJECT_ID}_ls:#{Feature::BOD_EXPRESSION_SUBJECT_ID}")['numFound']
          phrase_relations = name_term.child_relations
          flatten_all = expression_number <= root || phrase_relations.size==1
          sid = Spawnling.new do
            begin
              puts "#{Time.now}: Spawning sub-process #{Process.pid} for the collapse of #{name_term.prioritized_name(v).name} (T#{name_term.fid})."
              some_flattened = false
              for phrase_relation in phrase_relations
                phrase = phrase_relation.child_node
                expression_relations = phrase.child_relations
                if flatten_all || expression_relations.count <= 48
                  some_flattened = true
                  for expression_relation in expression_relations
                    expression = expression_relation.child_node
                    puts "#{Time.now}: Moving expression #{expression.prioritized_name(v).name} (T#{expression.fid})."
                    expression_relation.update_attribute(:parent_node_id, name_term.id)
                    expression.index!
                  end
                  puts "#{Time.now}: Deleting phrase #{phrase.prioritized_name(v).name} (T#{phrase.fid})."
                  phrase.child_relations.reload
                  phrase_relation.destroy
                  phrase.remove!
                  phrase.destroy
                end
              end
              if some_flattened
                puts "#{Time.now}: Reindexing name #{name_term.prioritized_name(v).name} (T#{name_term.fid})"
                name_term.child_relations.reload
                name_term.index!
              end
              puts "#{Time.now}: Finishing sub-process #{Process.pid}."
            rescue Exception => e
              STDERR.puts e.to_s
            end
          end
          Spawnling.wait([sid])
        end
      end
      Flare.commit
    end
    
    def run_tree_flattening_fixed
      v = View.get_by_code('roman.scholar')
      relation_type = FeatureRelationType.get_by_code('heads')
      Feature.roots.order(:position).collect(&:fid).each do |letter_fid|
        letter = Feature.get_by_fid(letter_fid)
        puts "#{Time.now}: Deleting names under letter #{letter.prioritized_name(v).name}..."
        destroy_features(get_term_fids_under_letter_by_phoneme(letter.fid, Feature::BOD_NAME_SUBJECT_ID))
        puts "#{Time.now}: Deleting phrases under letter #{letter.prioritized_name(v).name}..."
        destroy_features(get_term_fids_under_letter_by_phoneme(letter.fid, Feature::BOD_PHRASE_SUBJECT_ID))
        # there should not be children if index was correct
        destroy_features(letter.children.order(:fid).collect(&:fid))
        expressions = get_term_fids_under_letter_by_phoneme(letter.fid, Feature::BOD_EXPRESSION_SUBJECT_ID)
        head = nil
        sid = Spawnling.new do
          begin
            puts "#{Time.now}: Spawning sub-process #{Process.pid} for processing of expressions under letter #{letter.prioritized_name(v).name}..."
            expressions.each_index do |i|
              f = Feature.get_by_fid(expressions[i])
              if i % @fixed_size == 0
                head = f.clone_with_names
                FeatureRelation.create!(child_node: head, parent_node: letter, perspective: @tib_alpha, feature_relation_type: relation_type)
                head.subject_term_associations.create(subject_id: Feature::BOD_PHRASE_SUBJECT_ID, branch_id: Feature::BOD_PHONEME_SUBJECT_ID)
                head.update_attributes(is_public: true, position: f.position)
                puts "#{Time.now}: Created head #{head.prioritized_name(v).name} (#{head.fid}) under letter #{letter.prioritized_name(v).name}..."
              end
              FeatureRelation.create!(child_node: f, parent_node: head, perspective: @tib_alpha, feature_relation_type: relation_type)
            end
            puts "#{Time.now}: Finishing sub-process #{Process.pid}."
          rescue Exception => e
            STDERR.puts e.to_s
          end
        end
        Spawnling.wait([sid])
      end
      Flare.commit
    end
    
    private
    
    def get_term_fids_under_letter_by_phoneme(letter_fid, phoneme_sid)
      query = "tree:terms AND ancestor_ids_tib.alpha:#{letter_fid} AND associated_subject_#{Feature::BOD_PHONEME_SUBJECT_ID}_ls:#{phoneme_sid}"
      numFound = Feature.search_by(query)['numFound']
      resp = Feature.search_by(query, fl: 'uid', rows: numFound, sort: 'position_i asc')['docs']
      resp.collect{|f| f['uid'].split('-').last.to_i}
    end
    
    def destroy_features(fids)
      fids.each do |fid|
        f = Feature.get_by_fid(fid)
        if !f.nil?
          f.remove!
          f.destroy
          puts "#{Time.now}: Deleted term #{fid}."
        end
      end
    end
    
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
        a = f.subject_term_associations.create(subject_id: level_subject_id, branch_id: Feature::BOD_PHONEME_SUBJECT_ID)
        self.spreadsheet.imports.create!(item: a)
      end
      return f
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
