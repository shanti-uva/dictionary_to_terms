require "dictionary_to_terms/engine"

module DictionaryToTerms
  attr_accessor :spreadsheet
  
  def self.dictionary_database_yaml
    settings = Rails.cache.fetch('dictionary/database.yml/hash', :expires_in => 1.day) do
      settings_file = Rails.root.join('config', 'dictionary_database.yml')
      settings_file.exist? ? YAML.load_file(settings_file) : {}
    end
    settings[Rails.env]
  end
end
