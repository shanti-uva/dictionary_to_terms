module Dictionary
  class CategoryEtymologyAssociation < ApplicationRecord
    belongs_to :category
    belongs_to :etymology
  end
end