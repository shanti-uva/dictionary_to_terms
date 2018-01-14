module Dictionary
  class CategoryLiteraryQuotationAssociation < ApplicationRecord
    belongs_to :category
    belongs_to :literary_quotation
  end
end