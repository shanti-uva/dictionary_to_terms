module Dictionary
  class CategorySpellingAssociation < ApplicationRecord
    belongs_to :category
    belongs_to :spelling
  end
end
