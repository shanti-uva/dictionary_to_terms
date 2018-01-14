Rails.application.routes.draw do
  mount DictionaryToTerms::Engine => "/dictionary_to_terms"
end
