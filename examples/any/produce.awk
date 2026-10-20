# The universal path from a language with no crypto and no JSON at all (awk, here a stand-in
# for Wolfram Language, Fortran, COBOL, Stata, ...): write the data and a plain provenance;
# the action's mode sign pins and signs them in CI.
# Usage: mkdir -p DIR && awk -v dir=DIR -f produce.awk
BEGIN {
  csv = dir "/data.csv"
  print "x,y" > csv
  for (x = 1; x <= 3; x++) printf "%d,%d\n", x, x * x > csv
  close(csv)
  prov = dir "/data_provenance.json"
  print "{" > prov
  print "  \"name\": \"squares\"," > prov
  print "  \"source\": {\"url\": \"https://example.org/squares.csv\"}," > prov
  print "  \"resource\": {\"filename\": \"data.csv\", \"row_count_data_rows\": 3}" > prov
  print "}" > prov
  close(prov)
}
