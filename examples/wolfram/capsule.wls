#!/usr/bin/env wolframscript
(* The universal path from Wolfram Language: write the data and a plain provenance; the
   action's mode sign pins and signs them in CI.
   Usage: wolframscript -file capsule.wls <capsule dir> *)
dir = If[Length[$ScriptCommandLine] >= 2, $ScriptCommandLine[[2]], "capsule"];
Quiet[CreateDirectory[dir, CreateIntermediateDirectories -> True]];
rows = Table[{x, x^2}, {x, 3}];
Export[FileNameJoin[{dir, "data.csv"}], Prepend[rows, {"x", "y"}], "CSV"];
Export[FileNameJoin[{dir, "data_provenance.json"}],
  <|"name" -> "squares",
    "source" -> <|"url" -> "https://example.org/squares.csv"|>,
    "resource" -> <|"filename" -> "data.csv", "row_count_data_rows" -> Length[rows]|>|>,
  "RawJSON"];
Print["wrote ", dir, "/data.csv and data_provenance.json"];
