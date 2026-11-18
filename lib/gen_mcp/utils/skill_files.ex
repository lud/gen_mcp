defmodule GenMCP.Utils.SkillFiles do
  @moduledoc false

  @compile {:no_warn_undefined, :yamerl_constr}

  alias GenMCP.MCP.V2607.Skill
  alias GenMCP.MCP.V2607.SkillResource

  @type file_info :: %{path: String.t(), text?: boolean, mime_type: String.t()}

  @max_files_per_skill 512
  @max_bytes_per_skill 16 * 1024 * 1024
  @name_re ~r/^[a-z0-9]+(-[a-z0-9]+)*$/
  @name_max_length 64
  @frontmatter_re ~r/\A---\r?\n(?<yaml>.*?)^---[ \t]*\r?$/ms

  @spec skill_entry_from_path(Path.t(), String.t(), keyword) ::
          {Skill.t(), %{String.t() => file_info}}
  # sobelow_skip ["Traversal.FileModule"]
  def skill_entry_from_path(skill_md_path, base_uri, opts) do
    extensions = Keyword.get(opts, :extensions)
    root = Path.dirname(skill_md_path)

    frontmatter = skill_md_path |> File.read!() |> parse_frontmatter!(skill_md_path)
    %{"name" => name} = frontmatter
    check_name(name, skill_md_path)

    skill_uri = join_uri(base_uri, name)

    files =
      root
      |> list_files_sorted()
      |> Enum.filter(&(&1 == "SKILL.md" or keep_extension?(&1, extensions)))
      |> Enum.map(&describe_file(root, skill_uri, &1))

    check_limits(files, skill_md_path)

    skill = %Skill{
      uri: skill_uri <> "/SKILL.md",
      frontmatter: frontmatter,
      resources:
        Enum.map(files, fn file ->
          %SkillResource{uri: file.uri, digest: file.digest, size: file.size}
        end)
    }

    index =
      Map.new(files, fn file ->
        {file.uri, %{path: file.path, text?: file.text?, mime_type: file.mime_type}}
      end)

    {skill, index}
  end

  defp join_uri(base_uri, name) do
    encoded_name = encode_segment(name)

    if String.ends_with?(base_uri, "/") do
      base_uri <> encoded_name
    else
      base_uri <> "/" <> encoded_name
    end
  end

  defp encode_path(rel_path) do
    rel_path
    |> Path.split()
    |> Enum.map_join("/", &encode_segment/1)
  end

  defp encode_segment(segment) do
    URI.encode(segment, &URI.char_unreserved?/1)
  end

  defp keep_extension?(_rel_path, nil) do
    true
  end

  defp keep_extension?(rel_path, extensions) do
    Path.extname(rel_path) in extensions
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp describe_file(root, skill_uri, rel_path) do
    bytes = File.read!(Path.join(root, rel_path))

    %{
      path: rel_path,
      uri: skill_uri <> "/" <> encode_path(rel_path),
      digest: "sha256:" <> Base.encode16(:crypto.hash(:sha256, bytes), case: :lower),
      size: byte_size(bytes),
      text?: String.valid?(bytes),
      mime_type: MIME.from_path(rel_path)
    }
  end

  @spec list_files_sorted(Path.t()) :: [String.t()]
  def list_files_sorted(root) do
    root
    |> do_list_files("")
    |> Enum.sort()
  end

  defp do_list_files(root, rel_dir) do
    root
    |> Path.join(rel_dir)
    |> File.ls!()
    |> Enum.flat_map(fn entry ->
      rel_path =
        if rel_dir == "" do
          entry
        else
          Path.join(rel_dir, entry)
        end

      abs_path = Path.join(root, rel_path)

      case File.lstat!(abs_path).type do
        :directory ->
          do_list_files(root, rel_path)

        :regular ->
          [rel_path]

        :symlink ->
          symlinked_file(abs_path, rel_path)

        _ ->
          []
      end
    end)
  end

  defp symlinked_file(abs_path, rel_path) do
    if File.regular?(abs_path) do
      [rel_path]
    else
      []
    end
  end

  defp parse_frontmatter!(content, path) do
    yaml =
      case Regex.named_captures(@frontmatter_re, content) do
        %{"yaml" => yaml} -> yaml
        nil -> raise ArgumentError, "missing YAML frontmatter in #{path}"
      end

    frontmatter =
      case parse_yaml!(yaml, path) do
        [map] when is_map(map) -> normalize(map)
        _ -> raise ArgumentError, "YAML frontmatter in #{path} is not a mapping"
      end

    for key <- ["name", "description"] do
      if !is_binary(frontmatter[key]) do
        raise ArgumentError,
              "YAML frontmatter in #{path} must define #{inspect(key)} as a string"
      end
    end

    frontmatter
  end

  defp parse_yaml!(yaml, path) do
    case Application.ensure_all_started(:yamerl) do
      {:ok, _} ->
        :ok

      {:error, _} ->
        raise ArgumentError,
              "reading the skill frontmatter of #{path} requires the :yamerl dependency"
    end

    try do
      :yamerl_constr.string(yaml, [:str_node_as_binary, {:map_node_format, :map}])
    catch
      _kind, reason ->
        raise ArgumentError, "invalid YAML frontmatter in #{path}: #{inspect(reason)}"
    end
  end

  defp normalize(:null) do
    nil
  end

  defp normalize(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {normalize_key(key), normalize(value)} end)
  end

  defp normalize(list) when is_list(list) do
    Enum.map(list, &normalize/1)
  end

  defp normalize(atom) when is_atom(atom) and not is_boolean(atom) do
    Atom.to_string(atom)
  end

  defp normalize(scalar) do
    scalar
  end

  defp normalize_key(key) when is_binary(key) do
    key
  end

  defp normalize_key(key) when is_atom(key) or is_number(key) do
    to_string(key)
  end

  defp check_name(name, path) do
    if String.length(name) > @name_max_length or not Regex.match?(@name_re, name) do
      IO.warn(
        "skill name #{inspect(name)} in #{path} does not follow the Agent Skills naming rules: " <>
          "at most #{@name_max_length} lowercase letters, digits and single hyphens",
        []
      )
    end
  end

  defp check_limits(files, path) do
    count = length(files)
    bytes = Enum.sum_by(files, & &1.size)

    if count > @max_files_per_skill do
      IO.warn(
        "skill #{path} has #{count} files, hosts are only required to accept #{@max_files_per_skill}",
        []
      )
    end

    if bytes > @max_bytes_per_skill do
      IO.warn(
        "skill #{path} weighs #{bytes} bytes, hosts are only required to accept #{@max_bytes_per_skill}",
        []
      )
    end
  end
end
