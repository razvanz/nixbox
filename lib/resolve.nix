# Flatten project config into explicit fields with defaults.
# Plugins are imported and deep-merged before applying user overrides.
# Called via: nix eval --json --impure --expr '(import ./lib/resolve.nix { configPath = /path/to/.nixbox/config.nix; pluginsDir = ./plugins; })'
{
  configPath,
  pluginsDir ? null,
}:
let
  config = import configPath;

  defaultDomains = [
    "nixos.org"
  ];

  # --- Helpers (builtins only — no nixpkgs lib available) ---

  dedup =
    list:
    builtins.foldl' (acc: x: if builtins.elem x acc then acc else acc ++ [ x ]) [ ] list;

  # Deep-merge two attrsets:
  #   lists → concatenate
  #   attrsets → recurse
  #   scalars → right (overlay) wins
  deepMerge =
    base: overlay:
    builtins.foldl' (
      acc: key:
      let
        aVal = acc.${key} or null;
        bVal = overlay.${key} or null;
      in
      acc
      // {
        ${key} =
          if aVal == null then
            bVal
          else if bVal == null then
            aVal
          else if builtins.isList aVal && builtins.isList bVal then
            aVal ++ bVal
          else if builtins.isAttrs aVal && builtins.isAttrs bVal then
            deepMerge aVal bVal
          else
            bVal;
      }
    ) base (builtins.attrNames overlay);

  # --- Plugin resolution ---

  resolvePlugin =
    ref:
    if builtins.isPath ref then
      import ref
    else if builtins.substring 0 1 ref == "/" || builtins.substring 0 1 ref == "." then
      import (builtins.toPath ref)
    else
      import (pluginsDir + "/${ref}");

  pluginConfigs = map resolvePlugin (config.plugins or [ ]);

  # Strip meta fields before merging
  userConfig = builtins.removeAttrs config [ "plugins" ];

  # Base defaults for list/attrset fields
  defaults = {
    nix.packages = [ ];
    mounts = [ ];
    network.domains = defaultDomains;
    network.ports = [
      80
      443
    ];
    scripts = [ ];
    env = { };
    hooks = {
      pre-up = [ ];
      post-up = [ ];
      pre-down = [ ];
      post-down = [ ];
    };
  };

  # Merge order: defaults → plugins (in order) → user config
  merged = builtins.foldl' deepMerge defaults (pluginConfigs ++ [ userConfig ]);
in
{
  projectName = merged.name or (baseNameOf (dirOf (dirOf configPath)));
  resources = {
    vcpus = (merged.resources or { }).vcpus or 0;
    memoryMB = (merged.resources or { }).memoryMB or 0;
  };
  mounts =
    let
      raw = merged.mounts or [ ];
      effective =
        if raw == [ ] then
          [
            {
              source = ".";
              target = "~/workspace";
            }
          ]
        else
          raw;
    in
    map (m: {
      source = m.source;
      target = m.target;
      readonly = m.readonly or false;
    }) effective;
  network = {
    mode = (merged.network or { }).mode or "open";
    domains = dedup ((merged.network or { }).domains or defaultDomains);
    ports = dedup ((merged.network or { }).ports or [ 80 443 ]);
  };
  nix = {
    packages = dedup ((merged.nix or { }).packages or [ ]);
  };
  scripts = merged.scripts or [ ];
  env = merged.env or { };
  hooks = {
    pre-up = (merged.hooks or { }).pre-up or [ ];
    post-up = (merged.hooks or { }).post-up or [ ];
    pre-down = (merged.hooks or { }).pre-down or [ ];
    post-down = (merged.hooks or { }).post-down or [ ];
  };
}
