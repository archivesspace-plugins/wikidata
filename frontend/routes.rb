ArchivesSpace::Application.routes.draw do

  [AppConfig[:frontend_proxy_prefix], AppConfig[:frontend_prefix]].uniq.each do |prefix|

    scope prefix do
      match('/plugins/wikidata' => 'wikidata#index', :via => [:get])
      match('/plugins/wikidata/search' => 'wikidata#search', :via => [:get])
      match('/plugins/wikidata/import' => 'wikidata#import', :via => [:post])
    end
  end
end
