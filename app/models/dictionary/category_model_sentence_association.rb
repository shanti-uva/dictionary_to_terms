module Dictionary
  class CategoryModelSentenceAssociation < ApplicationRecord
    belongs_to :category
    belongs_to :model_sentence
  end
end