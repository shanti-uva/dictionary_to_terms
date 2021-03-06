# == Schema Info
# Schema version: 20100924060552
#
# Table name: definition_definition_forms
#
#  id                :integer         not null, primary key
#  def1_id           :integer
#  def2_id           :integer
#  created_by        :string(80)
#  relationship_from :string(256)
#  relationship_to   :string(256)
#  role              :string(128)
#  update_history    :text
#  updated_by        :string(80)
#  created_at        :string(80)
#  updated_at        :string(80)
module Dictionary
  class DefinitionDefinitionForm < DictionaryRecord
    belongs_to :definition_to, :class_name => "Definition", :foreign_key => "def2_id"
    belongs_to :definition_from, :class_name => "Definition", :foreign_key => "def1_id"
    has_one :meta, :foreign_key => 'definition_definition_form_id'

    def displayFromInfoPublic
      str = ""
      if relationship_to == 'future form' then
        str += "future tense"
      else
        if relationship_to == 'imperative form' then
        str += "imperative tense"
        else
          str += relationship_to unless relationship_to == nil
        end
      end
  
      return str
    end

    def displayFromTerm
      str = ""
      str += definition_to.term unless definition_to == nil or definition_to.term == nil
      return str
    end
  
  end
end