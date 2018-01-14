module Dictionary
  class CategoryPronunciationAssociation < ApplicationRecord
    belongs_to :category
    belongs_to :pronunciation
  end
end