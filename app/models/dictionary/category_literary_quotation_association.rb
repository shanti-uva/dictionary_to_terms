module Dictionary
  class CategoryLiteraryQuotationAssociation < DictionaryRecord
    belongs_to :category
    belongs_to :literary_quotation
  end
end