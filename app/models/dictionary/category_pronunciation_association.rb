module Dictionary
  class CategoryPronunciationAssociation < DictionaryRecord
    belongs_to :category
    belongs_to :pronunciation
  end
end