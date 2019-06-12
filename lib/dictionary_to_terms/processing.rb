module DictionaryToTerms
  class Processing
    attr_accessor :spreadsheet
    
    protected
    
    def add_subject_id(collection, subject_id, branch_id)
      if !subject_id.nil?
        options = { subject_id: subject_id }
        association = collection.where(options).first
        if association.nil?
          association = collection.create!(options.merge(branch_id: branch_id))
          self.spreadsheet.imports.create!(item: association)
        end
      end
    end
    
    def add_subject_text(collection, subject_text, branch_id)
      if !subject_text.blank?
        s = SubjectsIntegration::Feature.search_by("ancestor_uids_generic:subjects-#{branch_id} AND header:\"#{subject_text}\"")['docs'].first
        s = SubjectsIntegration::Feature.search_by("ancestor_uids_generic:subjects-#{branch_id} AND header:\"#{subject_text.split(' ').first}\"")['docs'].first if s.nil?
        if !s.nil?
          sid = s['uid'].split('-').last
          add_subject_id(collection, sid, branch_id)
        end
      end
    end
    
    def process_definition(word, source_def, parent_def = nil, position = 1)
      @default_language ||= Language.get_by_code('eng')
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
      return dest_def
    end
  end
end