module Dictionary
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true
    establish_connection(DictionaryToTerms.dictionary_database_yaml)
  end
end
