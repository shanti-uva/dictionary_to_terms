module Dictionary
  class CategoryTranslationEquivalentAssociation < DictionaryRecord
    belongs_to :category
    belongs_to :translation_equivalent
  end
end
