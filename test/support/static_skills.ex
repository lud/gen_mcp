defmodule GenMCP.Support.StaticSkills do
  @moduledoc false
  use GenMCP.Suite.SkillRepo.Static,
    otp_app: :gen_mcp,
    dir: "test_skills/main",
    prefix: "skill://test/"
end
