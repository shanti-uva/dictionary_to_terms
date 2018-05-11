module Dictionary
  class CategoryTranslationEquivalentAssociation < ApplicationRecord
    belongs_to :category
    belongs_to :translation_equivalent
  end
end
