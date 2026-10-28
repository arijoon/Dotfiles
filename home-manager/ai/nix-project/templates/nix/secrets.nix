{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.secrets;

  envs = lib.mapAttrs config.evalEnv config.envModules;

  sharedFile = "nix/envs/shared/secrets.yaml";
  fileOf = envName: "nix/envs/${envName}/secrets.yaml";
  debugFileOf = envName: "nix/envs/${envName}/debug-secrets.yaml";
  placeholder = "age1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq5cu47z";

  keyOf =
    name:
    let
      of = if name == config.envName then config else envs.${name};
    in
    {
      inherit name;
      inherit (of.secrets)
        restricted
        keyFile
        recipient
        debugKeyFile
        debugRecipient
        ;
    };

  keys = lib.genAttrs config.taskEnvs keyOf;

  restrictedNames = lib.filter (name: keys.${name}.restricted) config.taskEnvs;
  unrestrictedNames = lib.filter (name: !keys.${name}.restricted) config.taskEnvs;
  restrictedList =
    if restrictedNames == [ ] then
      "a restricted env, which this project doesn't have yet"
    else
      lib.concatStringsSep ", " restrictedNames;

  keyPathIn =
    home: base: file:
    if lib.hasPrefix "~/" file then
      ''"${home}"/${lib.escapeShellArg (lib.removePrefix "~/" file)}''
    else if lib.hasPrefix "/" file then
      lib.escapeShellArg file
    else
      ''"${base}"/${lib.escapeShellArg file}'';

  keyPath = keyPathIn "$HOME";

  keyNote =
    key:
    if key.restricted then
      "it lives outside the repository, where no agent or sandbox can read it, so run this yourself, restoring it there from your copy if it's missing"
    else
      "restore it there from your copy";

  regexOf = file: "^${lib.escapeRegex file}$";

  rulesWith =
    recipientOf: debugOf:
    let
      restrictedTo = map recipientOf restrictedNames;
      rule = file: recipients: {
        path_regex = regexOf file;
        age = lib.concatStringsSep "," (lib.unique recipients);
      };
    in
    {
      creation_rules =
        lib.optional (restrictedTo != [ ]) (rule sharedFile restrictedTo)
        ++ map (
          name:
          rule (fileOf name) ([ (recipientOf name) ] ++ lib.optionals (!keys.${name}.restricted) restrictedTo)
        ) config.taskEnvs
        ++ lib.concatMap (
          name:
          lib.optional (debugOf name != null) (
            rule (debugFileOf name) [
              (recipientOf name)
              (debugOf name)
            ]
          )
        ) config.taskEnvs;
    };

  rules = rulesWith (name: keys.${name}.recipient) (name: keys.${name}.debugRecipient);

  rulesJson = pkgs.writeText "sops-rules.json" (builtins.toJSON rules);

  sharing =
    name: lib.filter (other: keys.${other}.recipient == keys.${name}.recipient) unrestrictedNames;

  sopsYaml =
    name: rules:
    pkgs.writeText name (
      "creation_rules:\n"
      + lib.concatMapStrings (
        rule: "  - path_regex: ${rule.path_regex}\n    age: ${rule.age}\n"
      ) rules.creation_rules
    );

  sopsConfig = sopsYaml "sops.yaml" rules;

  sopsFiles =
    lib.optional (restrictedNames != [ ]) sharedFile
    ++ map fileOf config.taskEnvs
    ++ map debugFileOf (lib.filter (name: keys.${name}.debugRecipient != null) config.taskEnvs);

  load =
    key: debugOnly:
    let
      envFile = fileOf key.name;
      debugFile = debugFileOf key.name;
      keyFile = if debugOnly then key.debugKeyFile else key.keyFile;
      whose = if debugOnly then "${key.name}'s debug" else "${key.name}'s";
    in
    pkgs.writeShellApplication {
      name = "secrets-load-${key.name}${lib.optionalString debugOnly "-debug"}";
      runtimeInputs = [
        pkgs.sops
        pkgs.jq
        pkgs.coreutils
      ];
      text = ''
        root="$1" task="$2"
        shift 2
        identity=${keyPath "$root" keyFile}

        files=()
        decrypted=(${
          if debugOnly then debugFile else "${envFile} ${lib.optionalString key.restricted sharedFile}"
        })
        for spec in "$@"; do
          case "''${spec#+}" in
            @*)
              ${lib.optionalString (!debugOnly) "decrypted+=(${debugFile})"}
              break
              ;;
          esac
        done
        for file in "''${decrypted[@]}"; do
          [ ! -e "$root/$file" ] || files+=("$file")
        done

        shared='{}' own='{}' debug='{}'
        if [ "''${#files[@]}" -gt 0 ]; then
          if [ ! -f "$identity" ] || ! { : <"$identity"; } 2>/dev/null; then
            echo "secrets: task ${key.name} $task needs ${whose} age key, ${keyFile}, to decrypt ''${files[*]}, and can't read it; ${
              keyNote (key // lib.optionalAttrs debugOnly { restricted = false; })
            }" >&2
            exit 1
          fi
          for file in "''${files[@]}"; do
            if ! out="$(env -u SOPS_AGE_KEY -u SOPS_AGE_KEY_CMD SOPS_AGE_KEY_FILE="$identity" sops decrypt --output-type json "$root/$file")"; then
              echo "secrets: task ${key.name} $task couldn't decrypt $file with ${keyFile}" >&2
              exit 1
            fi
            case "$file" in
              ${envFile}) own="$out" ;;
              ${debugFile}) debug="$out" ;;
              *) shared="$out" ;;
            esac
          done
        fi

        entries="$(printf '%s\n' "$shared" "$own" "$debug" | jq -rs --args '
          .[0] as $shared
          | .[1] as $own
          | .[2] as $debug
          | $ARGS.positional[]
          | ltrimstr("+") as $spec
          | ($spec | ltrimstr("=") | ltrimstr("@")) as $key
          | (if $spec | startswith("=") then $own elif $spec | startswith("@") then $debug else $shared + $own end) as $from
          | if $from | has($key) then "\($key) \($from[$key] | if type == "string" then . else tojson end | @base64)"
            elif startswith("+") then "! \($spec)"
            else empty end
        ' "$@")"

        missing=()
        owned=()
        debugged=()
        lines=()
        while read -r key value; do
          case "$key $value" in
            " ") ;;
            "! ="*) owned+=("''${value#=}") ;;
            "! @"*) debugged+=("''${value#@}") ;;
            "! "*) missing+=("$value") ;;
            *) lines+=("$key $value") ;;
          esac
        done <<<"$entries"

        if [ "''${#missing[@]}" -gt 0 ]; then
          list="$(printf '%s, ' "''${missing[@]}")"
          echo "secrets: task ${key.name} $task needs ''${list%, }, ${
            if key.restricted then
              "which neither ${envFile} nor ${sharedFile} holds; add each with task ${key.name} secrets edit, or task ${key.name} shared-secrets edit for every env"
            else
              "which ${envFile} doesn't hold; ${key.name} never decrypts ${sharedFile}, which only ${restrictedList} can; add each with task ${key.name} secrets edit, or run the task under ${restrictedList}"
          }" >&2
        fi
        if [ "''${#owned[@]}" -gt 0 ]; then
          list="$(printf '%s, ' "''${owned[@]}")"
          echo "secrets: task ${key.name} $task needs ''${list%, } from ${envFile}, the env's own file, which doesn't hold it; ${sharedFile}'s is never used for it; add it with task ${key.name} secrets edit" >&2
        fi
        if [ "''${#debugged[@]}" -gt 0 ]; then
          list="$(printf '%s, ' "''${debugged[@]}")"
          echo "secrets: task ${key.name} $task needs ''${list%, } from ${debugFile}, the env's debug file, which doesn't hold it; add it with task ${key.name} debug-secrets init or edit" >&2
        fi
        if [ "''${#missing[@]}" -gt 0 ] || [ "''${#owned[@]}" -gt 0 ] || [ "''${#debugged[@]}" -gt 0 ]; then
          exit 1
        fi
        [ "''${#lines[@]}" -eq 0 ] || printf '%s\n' "''${lines[@]}"
      '';
    };

  loadFragment =
    key: declared:
    let
      debugKeys = declared.debug or [ ];
      mark =
        key:
        if lib.elem key debugKeys then
          "@${key}"
        else if lib.elem key (declared.own or [ ]) then
          "=${key}"
        else
          key;
      all = (declared.required or [ ]) ++ (declared.optional or [ ]);
      debugOnly = all != [ ] && lib.all (key: lib.elem key debugKeys) all;
      specs = map (key: "+${mark key}") (declared.required or [ ]) ++ map mark (declared.optional or [ ]);
    in
    lib.optionalString (declared != null && specs != [ ]) ''
      __secrets_specs=()
      __secrets_declared=(${lib.escapeShellArgs specs})
      for __secrets_spec in "''${__secrets_declared[@]}"; do
        __secrets_key="''${__secrets_spec#+}"
        __secrets_key="''${__secrets_key#=}"
        __secrets_key="''${__secrets_key#@}"
        [ -n "''${!__secrets_key+set}" ] || __secrets_specs+=("$__secrets_spec")
      done
      if [ "''${#__secrets_specs[@]}" -gt 0 ]; then
        __secrets_entries="$(${lib.getExe (load key debugOnly)} "$root" ${lib.escapeShellArg declared.name} "''${__secrets_specs[@]}")" || exit 1
        __secrets_ifs="$IFS"
        IFS=$'\n'
        for __secrets_line in $__secrets_entries; do
          export "''${__secrets_line%% *}=$(printf %s "''${__secrets_line#* }" | base64 -d)"
          SECRETS_LOADED="''${SECRETS_LOADED:+$SECRETS_LOADED }''${__secrets_line%% *}"
        done
        IFS="$__secrets_ifs"
        [ -z "''${SECRETS_LOADED:-}" ] || export SECRETS_LOADED
      fi
      unset __secrets_declared __secrets_specs __secrets_spec __secrets_key __secrets_entries __secrets_ifs __secrets_line
    '';

  editDir = name: ".secrets/edit/${name}";

  secretsCommand =
    {
      who,
      file,
      generate,
      key,
      editAs,
    }:
    let
      subcommands = "edit | show-keys" + lib.optionalString (generate != null) " | init";
    in
    ''
      usage() {
        echo "Usage: ${who} <${subcommands}>, on ${file}" >&2
      }

      sub="''${1:-}"
      if [ "$#" -ne 1 ]; then
        usage
        exit 1
      fi

      unset SOPS_AGE_KEY SOPS_AGE_KEY_CMD
      ${lib.optionalString (key != null) ''
        export SOPS_AGE_KEY_FILE=${keyPath "$PWD" key.keyFile}

        needs_key() {
          if [ ! -f "$SOPS_AGE_KEY_FILE" ] || ! { : <"$SOPS_AGE_KEY_FILE"; } 2>/dev/null; then
            echo "${who}: $1 needs ${key.name}'s age key, ${key.keyFile}, and can't read it; ${keyNote key}" >&2
            exit 1
          fi
        }
      ''}
      keys() {
        [ ! -e ${file} ] || yq -r 'del(.sops) | keys | .[]' ${file}
      }

      create() {
        [ ! -e ${file} ] || return 0
        mkdir -p "$(dirname ${file})"
        if ! printf '{}\n' | sops encrypt --filename-override ${file} --input-type yaml --output-type yaml /dev/stdin >${file}.new; then
          rm -f ${file}.new
          echo "${who}: sops couldn't create ${file}: .sops.yaml must have a rule for it with a real age recipient, not the placeholder" >&2
          exit 1
        fi
        mv ${file}.new ${file}
        echo "${who}: created ${file}" >&2
      }

      case "$sub" in
        edit)
          ${
            if key == null then
              ''
                echo "${who}: edit needs a restricted env's key: ${config.envName} never decrypts ${file}; run task <env> shared-secrets edit under ${restrictedList}" >&2
                exit 1
              ''
            else
              ''
                needs_key edit
                create
                rm -rf -- ${editDir editAs}
                (umask 077 && mkdir -p -- ${editDir editAs})
                export TMPDIR="$PWD/${editDir editAs}"
                exec sops edit ${file}
              ''
          }
          ;;
        show-keys)
          keys
          ;;
        ${lib.optionalString (generate != null) ''
          init)
            present="$(keys)"
            added=()
            generated=(${
              lib.escapeShellArgs (lib.mapAttrsToList (key: bytes: "${key}:${toString bytes}") generate)
            })
            for spec in "''${generated[@]}"; do
              key="''${spec%%:*}"
              bytes="''${spec#*:}"
              if grep -qxF -- "$key" <<<"$present"; then
                continue
              fi
              needs_key init
              create
              od -An -vtx1 -N"$bytes" /dev/urandom | tr -d ' \n' | jq -R . | sops set --value-stdin ${file} "[\"$key\"]"
              added+=("$key")
            done
            if [ "''${#added[@]}" -gt 0 ]; then
              echo "${who}: added ''${added[*]} to ${file}"
            else
              echo "${who}: ${
                if generate == { } then
                  "nothing to add: the env declares no secrets.generate"
                else
                  "${file} holds every generated key: ${lib.concatStringsSep ", " (lib.attrNames generate)}"
              }"
            fi
            ;;
        ''}
        *)
          usage
          exit 1
          ;;
      esac
    '';

  commandInputs = [
    pkgs.sops
    pkgs.yq-go
    pkgs.jq
    pkgs.gnugrep
    pkgs.coreutils
  ];
in
{
  options.secrets = {
    generate = lib.mkOption {
      type = lib.types.attrsOf lib.types.ints.positive;
      default = { };
      description = "Keys task <env> secrets init adds to the env's sops file when it lacks them, each that many random bytes, hex-encoded.";
    };

    sharedFile = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = sharedFile;
      description = "The sops file every env shares, relative to the repository root.";
    };

    fileOf = lib.mkOption {
      type = lib.types.functionTo lib.types.str;
      readOnly = true;
      default = fileOf;
      description = "An env's sops file, relative to the repository root, by the env's name.";
    };

    restricted = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether the env's key is its own, outside the repository and every
        sandbox, and decrypts the shared file too. An unrestricted env never
        decrypts the shared file, and its file is encrypted to every
        restricted env's key as well as its own.
      '';
    };

    keyFile = lib.mkOption {
      type = lib.types.str;
      default =
        if cfg.restricted then
          "~/.config/sops/age/${config.envName}.key"
        else
          ".secrets/${config.envName}.key";
      description = "The env's age identity, relative to the repository root or under ~/.";
    };

    recipient = lib.mkOption {
      type = lib.types.str;
      default = placeholder;
      description = "The public key of keyFile, which .sops.yaml encrypts the env's file to.";
    };

    debugRecipient = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "The public key of debugKeyFile. Set, .sops.yaml encrypts the env's debug file to it and the env's recipient; null, the env has no debug file.";
    };

    debugKeyFile = lib.mkOption {
      type = lib.types.str;
      default = ".secrets/${config.envName}-debug.key";
      description = "The env's debug age identity, relative to the repository root, gitignored; it decrypts the debug file alone.";
    };

    debugGenerate = lib.mkOption {
      type = lib.types.attrsOf lib.types.ints.positive;
      default = { };
      description = "Keys task <env> debug-secrets init adds to the env's debug file when it lacks them, each that many random bytes, hex-encoded.";
    };

    debugFileOf = lib.mkOption {
      type = lib.types.functionTo lib.types.str;
      readOnly = true;
      default = debugFileOf;
      description = "An env's debug sops file, relative to the repository root, by the env's name.";
    };

    keys = lib.mkOption {
      type = lib.types.raw;
      readOnly = true;
      default = keys;
      description = "Every env's name, restricted, keyFile and recipient, by name.";
    };

    loadFragment = lib.mkOption {
      type = lib.types.raw;
      readOnly = true;
      default = loadFragment;
      description = ''
        Shell fragment for an env's key (secrets.keys.<env>) and a task's
        declared secrets: decrypts the env's sops file, and the shared one for
        a restricted env, and exports the declared keys the caller hasn't set,
        naming each it exported in SECRETS_LOADED. Needs 'root'.
      '';
    };
  };

  config = {
    devshell.packages = [
      pkgs.sops
      pkgs.age
    ];

    tasks.secrets = {
      fresh = true;
      description = "The env's sops file, ${fileOf "<env>"}: edit | show-keys (names only) | init (adds missing generated values)";
      runtimeInputs = commandInputs;
      command = secretsCommand {
        who = "task ${config.envName} secrets";
        file = fileOf config.envName;
        inherit (cfg) generate;
        key = keyOf config.envName;
        editAs = config.envName;
      };
    };

    tasks.debug-secrets = {
      fresh = true;
      description = "The env's debug sops file, ${debugFileOf "<env>"}, with the debug key alone: edit | show-keys (names only) | init (adds missing generated values)";
      runtimeInputs = commandInputs;
      command = secretsCommand {
        who = "task ${config.envName} debug-secrets";
        file = debugFileOf config.envName;
        generate = cfg.debugGenerate;
        key = {
          name = "${config.envName}-debug";
          restricted = false;
          inherit (cfg) recipient;
          keyFile = cfg.debugKeyFile;
        };
        editAs = "${config.envName}-debug";
      };
    };

    tasks.shared-secrets = {
      fresh = true;
      description = "The sops file every env shares, ${sharedFile}, with a restricted env's key: edit | show-keys (names only)";
      runtimeInputs = commandInputs;
      command = secretsCommand {
        who = "task ${config.envName} shared-secrets";
        file = sharedFile;
        generate = null;
        key = if cfg.restricted then keyOf config.envName else null;
        editAs = "shared";
      };
    };

    tasks.sops-config = {
      fresh = true;
      description = "Write .sops.yaml: a creation rule per sops file, to the recipients the env modules declare";
      runtimeInputs = [ pkgs.coreutils ];
      command = ''
        cat ${sopsConfig} > .sops.yaml
        echo "sops-config: wrote .sops.yaml; sops updatekeys re-encrypts a file to its rule's recipients"
      '';
    };

    tasks.secrets-check = {
      description = "Fail on a committed secrets file with a plaintext value, outside .sops.yaml's rules or encrypted to recipients other than its rule's, or a .sops.yaml other than the env modules' rules";
      runtimeInputs = commandInputs ++ [ pkgs.git ];
      command = ''
        status=0
        fail() {
          echo "secrets-check: $*" >&2
          status=1
        }

        rules="$(yq -o=json '.creation_rules // []' .sops.yaml)" || {
          fail ".sops.yaml is missing or isn't YAML"
          rules='[]'
        }

        matched() {
          jq -e --arg path "$1" 'any(.[]; (.path_regex // "") as $re | $re != "" and ($path | test($re)))' <<<"$rules" >/dev/null
        }

        plaintext() {
          yq -o=json "$1" | jq -r '
            (del(.sops) | paths(scalars) as $p
              | select(getpath($p) | tostring | test("^ENC\\[AES256_GCM,data:[^,]*,iv:[^,]+,tag:[^,]+,type:[a-z]+\\]$") | not)
              | $p | map(tostring) | join(".")),
            (if (.sops.mac // "") | tostring | startswith("ENC[AES256_GCM,") then empty else "sops.mac" end)'
        }

        recipients() {
          yq -o=json "$1" | jq -c '.sops // {} | [((.age // [])[] | .recipient // empty), (to_entries[] | select(.key != "age" and (.value | type) == "array") | .key as $kind | .value[] | "\($kind) \(tojson)")] | unique'
        }

        wanted() {
          jq -c --arg path "$2" '[first(.creation_rules[] | select(.path_regex as $re | $path | test($re))) | .age | split(",")[]] | unique' "$1"
        }

        pinned() {
          jq -rn --argjson want "$(wanted "$1" "$2")" --argjson got "$(recipients "$3")" '
            ($got - $want) as $extra
            | ($want - $got) as $missing
            | (if $extra == [] then empty else "is encrypted to \($extra | join(", ")), which its rule doesn'"'"'t list" end),
              (if $missing == [] then empty else "isn'"'"'t encrypted to \($missing | join(", ")), which its rule lists" end)'
        }

        nixRules=${rulesJson}
        jq -e --argjson have "$(yq -o=json . .sops.yaml 2>/dev/null || echo null)" '. == $have' "$nixRules" >/dev/null \
          || fail ".sops.yaml isn't the rules the env modules' recipients give: write it with task sops-config, then re-encrypt each file with sops updatekeys"

        tmp="$(mktemp -d)"
        trap 'rm -rf "$tmp"' EXIT
        printf 'PLAIN: value\n' > "$tmp/plain.yaml"
        [ -n "$(plaintext "$tmp/plain.yaml")" ] || fail "the plaintext scan finds nothing in a plaintext file"
        ! matched nix/envs/secrets-check-unmatched/secrets.yaml || fail ".sops.yaml's rules match nix/envs/secrets-check-unmatched/secrets.yaml, so the rule check can't fail"

        committed=0
        while IFS= read -r -d "" file; do
          committed=$((committed + 1))
          matched "$file" || fail "$file is a secrets file no creation rule in .sops.yaml matches"
          while IFS= read -r leaf; do
            [ -z "$leaf" ] || fail "$file holds $leaf in plaintext, not sops-encrypted"
          done < <(plaintext "$file" || echo "(the whole file: it isn't YAML)")
          while IFS= read -r problem; do
            [ -z "$problem" ] || fail "$file $problem"
          done < <(pinned "$nixRules" "$file" "$file" || echo "has recipients that can't be read")
        done < <(git ls-files -z --cached --others --exclude-standard -- '*secrets.yaml' '*secrets.yml' '*secrets.json')

        expected=(${lib.escapeShellArgs sopsFiles})
        for path in "''${expected[@]}"; do
          matched "$path" || fail ".sops.yaml has no creation rule for $path"
        done

        if [ "$status" -eq 0 ]; then
          echo "secrets-check: $committed committed secrets file(s), each matched by .sops.yaml, which holds the env modules' rules, encrypted to its rule's recipients alone, with every value encrypted"
          ${lib.concatMapStrings (name: ''
            echo ${lib.escapeShellArg "secrets-check: ${name} is restricted, but its recipient is also ${lib.concatStringsSep " and " (sharing name)}'s, so ${lib.concatStringsSep " and " (map (other: keys.${other}.keyFile) (sharing name))} still decrypts ${fileOf name} and ${sharedFile}: give ${name} its own key"}
          '') (lib.filter (name: sharing name != [ ]) restrictedNames)}
          if grep -qF ${placeholder} .sops.yaml; then
            echo "secrets-check: .sops.yaml still encrypts to the placeholder recipient: an env's secrets.recipient isn't set"
          fi
        fi
        exit "$status"
      '';
    };

    checks.steps = [ "secrets-check" ];
  };
}
