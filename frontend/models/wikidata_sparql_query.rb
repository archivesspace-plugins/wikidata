# SPARQL query template for fetching Wikidata entity data.
# Replaces Q_PLACEHOLDER with the actual Q number (e.g., Q42).
# Returns propertyName and value for each Wikidata property.
module WikidataSparqlQuery
  QUERY_TEMPLATE = <<~SPARQL.freeze
    SELECT ?propertyName ?value WHERE {
      {
        wd:Q_PLACEHOLDER wdt:P735 ?givenNameEntity .
        ?givenNameEntity rdfs:label ?value .
        FILTER(LANG(?value) IN ("en", "mul"))
        BIND("givenName" as ?propertyName)
      }
      UNION
      {
        wd:Q_PLACEHOLDER wdt:P734 ?familyNameEntity .
        ?familyNameEntity rdfs:label ?value .
        FILTER(LANG(?value) IN ("en", "mul"))
        BIND("familyName" as ?propertyName)
      }
      UNION
      {
        wd:Q_PLACEHOLDER wdt:P8017 ?generationalSuffixEntity .
        ?generationalSuffixEntity rdfs:label ?value .
        FILTER(LANG(?value) IN ("en", "mul"))
        BIND("generationalSuffix" as ?propertyName)
      }
      UNION
      {
        wd:Q_PLACEHOLDER wdt:P511 ?honorificPrefixEntity .
        ?honorificPrefixEntity rdfs:label ?value .
        FILTER(LANG(?value) IN ("en", "mul"))
        BIND("honorificPrefix" as ?propertyName)
      }
      UNION
      {
        wd:Q_PLACEHOLDER wdt:P742 ?value .
        BIND("pseudonym" as ?propertyName)
      }
      UNION
      {
        wd:Q_PLACEHOLDER wdt:P569 ?value .
        BIND("dateOfBirth" as ?propertyName)
      }
      UNION
      {
        wd:Q_PLACEHOLDER wdt:P571 ?value .
        BIND("inception" as ?propertyName)
      }
      UNION
      {
        wd:Q_PLACEHOLDER wdt:P570 ?value .
        BIND("dateOfDeath" as ?propertyName)
      }
      UNION
      {
        wd:Q_PLACEHOLDER wdt:P576 ?value .
        BIND("dissolvedDate" as ?propertyName)
      }
      UNION
      {
        # Wikidata stores a precision (9=year, 10=month, 11=day) per date value.
        # The truthy wdt: dates above normalise year/month precision to YYYY-01-01,
        # so we fetch the precision to standardise dates at the correct granularity.
        wd:Q_PLACEHOLDER p:P569/psv:P569 ?dobValueNode .
        ?dobValueNode wikibase:timePrecision ?value .
        BIND("dateOfBirthPrecision" as ?propertyName)
      }
      UNION
      {
        wd:Q_PLACEHOLDER p:P570/psv:P570 ?dodValueNode .
        ?dodValueNode wikibase:timePrecision ?value .
        BIND("dateOfDeathPrecision" as ?propertyName)
      }
      UNION
      {
        wd:Q_PLACEHOLDER p:P571/psv:P571 ?incValueNode .
        ?incValueNode wikibase:timePrecision ?value .
        BIND("inceptionPrecision" as ?propertyName)
      }
      UNION
      {
        wd:Q_PLACEHOLDER p:P576/psv:P576 ?dissValueNode .
        ?dissValueNode wikibase:timePrecision ?value .
        BIND("dissolvedDatePrecision" as ?propertyName)
      }
      UNION
      {
        wd:Q_PLACEHOLDER rdfs:label ?value .
        FILTER(LANG(?value) = "en")
        BIND("label" as ?propertyName)
      }
      UNION
      {
        wd:Q_PLACEHOLDER schema:description ?value .
        FILTER(LANG(?value) = "en")
        BIND("description" as ?propertyName)
      }
      UNION
      {
        BIND("Q_PLACEHOLDER" as ?value)
        BIND("qNumber" as ?propertyName)
      }
      UNION
      {
        wd:Q_PLACEHOLDER wdt:P244 ?value .
        BIND("libraryOfCongressAuthorityId" as ?propertyName)
      }
      UNION
      {
        wd:Q_PLACEHOLDER wdt:P3430 ?value .
        BIND("snacArkId" as ?propertyName)
      }
      UNION
      {
        wd:Q_PLACEHOLDER wdt:P214 ?value .
        BIND("viafClusterId" as ?propertyName)
      }
      UNION
      {
        wd:Q_PLACEHOLDER skos:altLabel ?value .
        FILTER(LANG(?value) = "en")
        BIND("alias" as ?propertyName)
      }
      UNION
      {
        wd:Q_PLACEHOLDER wdt:P31 ?instanceOfEntity .
        ?instanceOfEntity rdfs:label ?value .
        FILTER(LANG(?value) = "en")
        BIND("instanceOf" as ?propertyName)
      }
      UNION
      {
        wd:Q_PLACEHOLDER wdt:P31 ?instanceQidEntity .
        BIND(REPLACE(STR(?instanceQidEntity), "^.*/", "") as ?value)
        BIND("instanceQid" as ?propertyName)
      }
      UNION
      {
        wd:Q_PLACEHOLDER p:P31/ps:P31 wd:Q5 .
        BIND("true" as ?value)
        BIND("isHuman" as ?propertyName)
      }
      UNION
      {
        wd:Q_PLACEHOLDER wdt:P31/wdt:P279* wd:Q8436 .
        BIND("true" as ?value)
        BIND("isFamily" as ?propertyName)
      }
      UNION
      {
        wd:Q_PLACEHOLDER wdt:P31/wdt:P279* wd:Q106668099 .
        BIND("true" as ?value)
        BIND("isCorporateBody" as ?propertyName)
      }
      UNION
      {
        ?article schema:about wd:Q_PLACEHOLDER ;
                 schema:isPartOf <https://en.wikipedia.org/> .
        BIND(STR(?article) as ?value)
        BIND("wikipediaUrl" as ?propertyName)
      }
    }
  SPARQL

  def self.query_for(qid)
    normalized = qid.to_s.upcase.strip
    normalized = "Q#{normalized}" unless normalized.start_with?('Q')
    QUERY_TEMPLATE.gsub('Q_PLACEHOLDER', normalized)
  end
end
