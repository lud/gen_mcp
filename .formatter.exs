locals_without_parens = []

[
  import_deps: [:phoenix, :jsv, :plug],
  inputs: ["*.exs", "{config,lib,test,tmp,tools}/**/*.{ex,exs}"],
  force_do_end_blocks: true,
  locals_without_parens: locals_without_parens,
  export: [locals_without_parens: locals_without_parens]
]
