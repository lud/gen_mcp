locals_without_parens = [defcasterror: 3]

[
  plugins: [Quokka],
  quokka: [
    autosort: [],
    exclude: [
      # Do not turn assert into refute
      :tests
    ]
  ],
  import_deps: [:phoenix, :jsv, :plug],
  inputs: ["*.exs", "{config,lib,test,tmp,tools}/**/*.{ex,exs}"],
  force_do_end_blocks: true,
  locals_without_parens: locals_without_parens
]
