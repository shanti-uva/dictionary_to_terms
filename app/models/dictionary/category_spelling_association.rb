module Dictionary
  class CategorySpellingAssociation < DictionaryRecord
    belongs_to :category
    belongs_to :spelling
  end
end
