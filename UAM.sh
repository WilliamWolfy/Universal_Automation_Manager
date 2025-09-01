#!/usr/bin/env bash
# ================================================================
# Universal Automation Manager (UAM)
# Auteur / Author : WilliamWolfy
#
# EN :
# UAM — Manage, install and automate everything, everywhere
#
# - More than just a package manager:
#   create, organize and execute complete installation 
#   and configuration profiles.
# - All profiles and tasks are externalized in JSON files.
# - Works on Linux (apt, snap, …) and Windows (winget, UnigetUI).
# - Full support: JSON and CSV export/import.
#
# FR :
# UAM — Gérez, installez et automatisez tout, partout
#
# - Plus qu’un simple gestionnaire de paquets :
#   créez, organisez et exécutez des profils complets d’installation 
#   et de configuration.
# - Tous les profils et tâches sont externalisés dans des fichiers JSON.
# - Fonctionne sous Linux (apt, snap, …) et Windows (winget, UnigetUI).
# - Support complet : export/import JSON et CSV.
# ================================================================

# ================================================================
# EN : Configuration variable
# FR : Variable de configuration
# ================================================================
scriptName="Universal Automation Manager"
scriptAlias="UAM"
scriptCreator="William Wolfy"
scriptVersion="25.09.01"           # ⚠️ Pense à aligner avec version.txt sur GitHub
url_script="https://raw.githubusercontent.com/WilliamWolfy/Universal_Automation_Manager/refs/heads/main/UAM.sh"

url_scriptSource="${url_script%/*}/" 
scriptRepertory="$(pwd)"

VERSION_FILE="version.txt"
LANG_FILE="lang.json"
CURRENT_LANG="fr"
TASKS_FILE="tasks.json"
PROFILES_FILE="profiles.json"

# ================================================================
# EN : Display Utilities
# FR : Utilitaires d'affichage
# ================================================================
function echoColor {
  local color="$1"; shift
  local text="$*"
  local default="\033[0m"
  declare -A c=(
    ["black"]="\033[30m" ["red"]="\033[31m" ["green"]="\033[32m"
    ["yellow"]="\033[33m" ["blue"]="\033[34m" ["magenta"]="\033[35m"
    ["cyan"]="\033[36m" ["white"]="\033[37m" ["default"]="\033[0m"
  )
  if [[ -n "${c[$color]}" ]]; then
    echo -e "${c[$color]}$text$default"
  else
    echo -e "$text"
  fi
}

function title {
  local text="$1"
  local symbole="${2:--}"
  local color="${3:-default}"
  local long=$((${#text} + 4))
  local separator
  separator="$(printf "%${long}s" | tr ' ' "$symbole")"
  echoColor "$color" "$separator"
  echoColor "$color" "$symbole $text $symbole"
  echoColor "$color" "$separator"
  echo ""
}

function echoInfo { echo ""; echoColor "yellow" "ℹ️  $*"; echo ""; }
function echoCheck { echo ""; echoColor "green" "✅ $*"; echo ""; }
function echoError { echo ""; echoColor "red" "❌ $*"; echo ""; }
function echoWarn { echo ""; echoColor "yellow" "⚠️ $*"; echo ""; }

loadLang() {
    loadJsonToArray "$LANG_FILE" LANG_ARRAY || return 1


}

# ================================================================
# lang
# ----------------------------------------------------------------
# EN: Print a localized string resolved from LANG_ARRAY.
#     - Namespace = $functionName from caller, else ${FUNCNAME[1]}.
#     - Fallback to English, else humanized key.
#     - If missing: propose opening Google Translate, prompt for translation,
#       write back into lang.json under the right namespace, reload array.
#     - Appends suffix (e.g., "!", "...") and a trailing newline.
# FR : Affiche une chaîne localisée depuis LANG_ARRAY.
#      - Espace de noms = $functionName du caller, sinon ${FUNCNAME[1]}.
#      - Repli sur l’anglais, sinon clé humanisée.
#      - Si manquante : propose Google Traduction, demande la traduction,
#        enregistre au bon endroit dans lang.json, recharge le tableau.
#      - Ajoute le suffixe (ex: "!", "...") et un retour à la ligne.
# ================================================================
lang() {
  local key="$1"; shift
  local suffix="$*"

  # 0) Déterminer le namespace (NE PAS déclarer 'local functionName' dans lang())
  local ns=""
  if [[ -n "${functionName:-}" && "${functionName}" != "lang" ]]; then
    ns="$functionName"
  elif (( ${#FUNCNAME[@]} >= 2 )); then
    # Premier appelant réel
    local caller="${FUNCNAME[1]}"
    [[ "$caller" != "lang" && "$caller" != "source" ]] && ns="$caller"
  fi

  # Clé pleinement qualifiée (ex: "runTask.downloading")
  local fq_key="${ns:+$ns.}$key"

  # 1) Lookup dans la langue courante (namespace -> racine)
  local text="${LANG_ARRAY[$fq_key.$CURRENT_LANG]}"
  [[ -z "$text" ]] && text="${LANG_ARRAY[$key.$CURRENT_LANG]}"

  # 2) S’il manque : fallback + demande de traduction
  if [[ -z "$text" ]]; then
    # Base anglaise (namespace -> racine), sinon clé humanisée
    local en="${LANG_ARRAY[$fq_key.en]}"
    [[ -z "$en" ]] && en="${LANG_ARRAY[$key.en]}"
    local placeholder="${key//_/ }"
    local base="${en:-$placeholder}"

    # Copier la base dans le presse-papier (si possible)
    if command -v xclip >/dev/null 2>&1; then
      printf "%s" "$base" | xclip -selection clipboard
    elif command -v pbcopy >/dev/null 2>&1; then
      printf "%s" "$base" | pbcopy
    fi

    # Proposer l’ouverture de Google Translate
    local ask_open="${LANG_ARRAY[offer_translate.$CURRENT_LANG]}"
    [[ -z "$ask_open" ]] && ask_open="${LANG_ARRAY[offer_translate.en]:-Do you want to open Google Translate to help translate into %s? (y/n): }"
    local prompt_open
    printf -v prompt_open "$ask_open" "$CURRENT_LANG"
    local ans=""
    read -r -p "$prompt_open" ans
    if [[ "$ans" =~ ^[YyOo]$ ]]; then
      local encoded
      encoded=$(printf "%s" "$base" | jq -sRr @uri)
      local url="https://translate.google.com/?sl=en&tl=$CURRENT_LANG&text=$encoded"
      { command -v xdg-open >/dev/null 2>&1 && xdg-open "$url" >/dev/null 2>&1; } \
      || { command -v open >/dev/null 2>&1 && open "$url" >/dev/null 2>&1; }
    fi

    # Demander la traduction (ne pas rappeler lang() ici)
    local ask_provide="${LANG_ARRAY[provide_translation.$CURRENT_LANG]}"
    [[ -z "$ask_provide" ]] && ask_provide="${LANG_ARRAY[provide_translation.en]:-Provide translation for \"%s\" in %s: }"
    local prompt_provide
    printf -v prompt_provide "$ask_provide" "$base" "$CURRENT_LANG"
    local newval=""
    read -r -p "$prompt_provide" newval

    if [[ -n "$newval" ]]; then
      # Écrire dans lang.json sous le bon namespace
      if [[ -n "$ns" ]]; then
        jq --arg f "$ns" --arg k "$key" --arg l "$CURRENT_LANG" --arg v "$newval" '
          .[$f] = (.[$f] // {}) |
          .[$f][$k] = (.[$f][$k] // {}) |
          .[$f][$k][$l] = $v
        ' lang.json > lang.tmp && mv lang.tmp lang.json
      else
        jq --arg k "$key" --arg l "$CURRENT_LANG" --arg v "$newval" '
          .[$k] = (.[$k] // {}) |
          .[$k][$l] = $v
        ' lang.json > lang.tmp && mv lang.tmp lang.json
      fi
      # Recharger le tableau aplati
      loadJsonToArray lang.json LANG_ARRAY
      text="$newval"
    else
      text="$base"
    fi
  fi

  # 3) Impression finale (avec suffixe éventuel)
  printf "%s%s\n" "$text" "$suffix"
}

###############################################################################
# translate
# -----------------------------------------------------------------------------
# EN: Ask user to translate a text (with optional Google Translate helper).
# FR: Demande à l’utilisateur de traduire un texte (avec aide Google Translate).
###############################################################################
translate() {
    local functionName="translate"
    local original="$1"      # Texte original
    local target_lang="$2"   # Langue cible
    local translation=""

    # --- Demander texte si vide
    if [[ -z "$original" ]]; then
        local prompt_enter
        prompt_enter="$(lang enter_text_to_translate)"
        read -r -p "📝 $prompt_enter " original
    fi
    if [[ -z "$original" ]]; then
        echo "⏹️ $(lang no_text_provided)"
        return 1
    fi

    # --- Définir langue cible par défaut = en
    [[ -z "$target_lang" ]] && target_lang="en"

    # --- Proposer Google Translate
    local ans=""
    read -r -p "🌍 $(printf "$(lang offer_google_translate)" "$target_lang") (y/n): " ans
    if [[ "$ans" =~ ^[YyOo]$ ]]; then
        # Copier le TEXTE ORIGINAL dans le presse-papier
        if command -v xclip >/dev/null 2>&1; then
            printf "%s" "$original" | xclip -selection clipboard
        elif command -v pbcopy >/dev/null 2>&1; then
            printf "%s" "$original" | pbcopy
        fi

        # Ouvrir Google Translate
        local encoded
        encoded=$(printf "%s" "$original" | jq -sRr @uri)
        local url="https://translate.google.com/?sl=auto&tl=$target_lang&text=$encoded"
        { command -v xdg-open >/dev/null 2>&1 && xdg-open "$url" >/dev/null 2>&1; } \
        || { command -v open >/dev/null 2>&1 && open "$url" >/dev/null 2>&1; }
    fi

    # --- Demander traduction
    read -r -p "✏️ $(printf "$(lang provide_translation)" "$target_lang") " translation

    # --- Vérification systématique
    local confirm=""
    if [[ -z "$translation" ]]; then
        read -r -p "⚠️ $(lang confirm_no_translation) (y/n): " confirm
        if [[ ! "$confirm" =~ ^[YyOo]$ ]]; then
            return 1
        fi
    else
        read -r -p "✅ $(lang confirm_translation) \"$translation\" (y/n): " confirm
        if [[ ! "$confirm" =~ ^[YyOo]$ ]]; then
            return 1
        fi
    fi

    # --- Retourner traduction
    echo "$translation"
    return 0
}

# ================================================================
# Infos script
# ================================================================

function scriptInformation {
    clear
    title "$(lang welcome) $scriptName ($scriptAlias)" "#" "blue"
    title "by $scriptCreator" "/" "white"
    echoColor "red" "Version: $scriptVersion"
    echo ""
}

# ================================================================
# askQuestion
# ----------------------------------------------------------------
# FR : Gère différents types de questions : Ouvert (QO), Oui/Non (QF), Choix multiple (QCM), Nombre (QN)
# Renvoie la réponse dans la variable : $response
# EN : Handles different question types: Open (QO), Yes/No (QF), Multiple Choice (QCM), Number (QN)
# Returns answer in variable: $response
# ================================================================
function askQuestion() {
    local prompt="$1"
    local qtype="${2:-QO}"
    shift 2
    local options=("$@")
    response=""

    case "$qtype" in
        QO) 
            read -rp "$prompt: " response
            ;;

        QF) 
            local yes_list=("Y" "Yes" "O" "Oui" "1")
            local no_list=("N" "No" "Non" "2")
            local answer=""
            while true; do
                echo -e "$prompt\n1) Yes\n2) No"
                read -rp "Choice: " answer
                answer="${answer^}"  # Capitalize first letter
                if [[ " ${yes_list[*]} " == *" $answer "* ]]; then
                    response="Yes"
                    break
                elif [[ " ${no_list[*]} " == *" $answer "* ]]; then
                    response="No"
                    break
                else
                    echo "Invalid choice, try again."
                fi
            done
            ;;

        QCM)
            local min=0 max=0
            local mod=""
            # Check if first argument is limit
            if [[ "$1" =~ ^([+-]?[0-9]+)$ ]]; then
                mod="$1"
                shift
                options=("$@")
            fi
            local n_options=${#options[@]}
            local selected=()
            while true; do
                echo "$prompt"
                for i in "${!options[@]}"; do
                    printf "%d) %s\n" $((i+1)) "${options[$i]}"
                done
                read -rp "Enter numbers separated by spaces (0 to cancel): " input
                [[ "$input" == "0" ]] && response="CANCEL" && return

                selected=()
                valid=true
                for num in $input; do
                    if ! [[ "$num" =~ ^[0-9]+$ ]] || (( num < 1 || num > n_options )); then
                        valid=false
                        break
                    fi
                    selected+=("${options[$((num-1))]}")
                done
                if ! $valid; then
                    echo "Invalid selection, try again."
                    continue
                fi

                # Apply limits if mod is set
                if [[ -n "$mod" ]]; then
                    if [[ "$mod" =~ ^\+([0-9]+)$ ]]; then
                        (( ${#selected[@]} < ${BASH_REMATCH[1]} )) && { echo "Select at least ${BASH_REMATCH[1]} items."; continue; }
                    elif [[ "$mod" =~ ^-([0-9]+)$ ]]; then
                        (( ${#selected[@]} > ${BASH_REMATCH[1]} )) && { echo "Select at most ${BASH_REMATCH[1]} items."; continue; }
                    else
                        (( ${#selected[@]} != mod )) && { echo "Select exactly $mod items."; continue; }
                    fi
                fi
                break
            done
            response="${selected[*]}"
            ;;

        QN)
            local min=${1:-}
            local max=${2:-}
            local number=""
            while true; do
                local prompt_text="$prompt"
                [[ -n "$min" && -n "$max" ]] && prompt_text+=" ($min-$max)"
                [[ -n "$min" && -z "$max" ]] && prompt_text+=" (>= $min)"
                [[ -z "$min" && -n "$max" ]] && prompt_text+=" (<= $max)"
                read -rp "$prompt_text: " number
                if ! [[ "$number" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
                    echo "Please enter a valid number."
                    continue
                fi
                [[ -n "$min" && "$number" -lt "$min" ]] && { echo "Number too small."; continue; }
                [[ -n "$max" && "$number" -gt "$max" ]] && { echo "Number too large."; continue; }
                response="$number"
                break
            done
            ;;

        *)
            echo "Unknown question type: $qtype"
            ;;
    esac
}

# ================================================================
# FONCTIONS UTILITAIRES
# ================================================================

# ============================================================
# detectOS
# ------------------------------------------------------------
# FR : Détection du système d'exploitation sur lequel le script s'éxécute.
# EN : Detection of the operating system on which the script is running.
# ============================================================
function detectOS {
    OS_FAMILY="$(lang unknown)"
    OS_DISTRO="$(lang unknown)"
    OS_VERSION="$(lang unknown)"

    case "$(uname -s)" in
        Linux*)
            OS_FAMILY="Linux"
            if [[ -f /etc/os-release ]]; then
                # Lecture des infos depuis os-release
                . /etc/os-release
                OS_DISTRO="$ID"
                OS_VERSION="$VERSION_ID"
            fi
            ;;
        Darwin*)
            OS_FAMILY="macOS"
            OS_DISTRO=$(sw_vers -productName)
            OS_VERSION=$(sw_vers -productVersion)
            ;;
        MINGW*|CYGWIN*|MSYS*|Windows_NT)
            OS_FAMILY="Windows"
            # Utiliser PowerShell pour obtenir la version exacte
            OS_DISTRO=$(powershell -Command "(Get-ComputerInfo).WindowsProductName" 2>/dev/null | tr -d '\r')
            OS_VERSION=$(powershell -Command "(Get-ComputerInfo).WindowsVersion" 2>/dev/null | tr -d '\r')
            ;;
        *)
            OS_FAMILY="$(lang unknown)"
            OS_DISTRO="$(lang unknown)"
            OS_VERSION="$(lang unknown)"
            ;;
    esac

    echoInfo "🖥️ OS : $OS_FAMILY / $OS_DISTRO / $OS_VERSION"
}

# ============================================================
# checkInternet
# ------------------------------------------------------------
# FR : Vérifie que la connexion internet soit disponible.
# EN : Check that the internet connection is available.
# ============================================================
function checkInternet {
    local verbose="$1"

    if [ "$verbose" ]; then echo "🔎 $(lang check_internet)"; fi
    if command -v curl >/dev/null 2>&1; then
        if curl -I -m 5 -s https://github.com >/dev/null; then
        if [ "$verbose" ]; then echoCheck "$(lang internet_ok)."; fi
        return 0
        fi
    fi
    # fallback ping (Linux: -c ; Windows: -n)
    if ping -c 1 github.com >/dev/null 2>&1 || ping -n 1 github.com >/dev/null 2>&1; then
        if [ "$verbose" ]; then echoCheck "$(lang internet_ok)."; fi
        return 0
    fi
    if [ "$verbose" ]; then echoError "$(lang internet_fail)."; fi
    exit 1
}

# ============================================================
# download
# ------------------------------------------------------------
# FR : Fonction de téléchargement utilisant la commande approprié par rapport au système.
# EN : Download function using the appropriate command in relation to the system.
# ============================================================
download() {
    local url="$1"
    local sortie="$2"
    local result=""

    if [ checkInternet ]; then
        if [[ -z "$sortie" ]]; then
            # Mode lecture dans stdout
            if command -v curl >/dev/null 2>&1; then
                result=$(curl -sL "$url")
            else
                result=$(wget -qO- "$url")
            fi
            echo "$result"
            return 0
        else
            # Mode écriture dans file
            if command -v curl >/dev/null 2>&1; then
                curl -sL -o "$sortie" "$url"
            else
                wget -qO "$sortie" "$url"
            fi
            return 0
        fi
    else
        echoWarn "$(lang internet_fail)"
        return 1
    fi
}

# ================================================================
# checkJson
# ----------------------------------------------------------------
# EN: Check if a JSON file exists, otherwise download it from repo.
#     - Uses checkInternet and download() from the script.
#     - Base URL: GitHub repo (Prototype-multi-langue branch).
# FR : Vérifie si un fichier JSON existe, sinon le télécharge depuis
#      le dépôt GitHub.
#      - Utilise checkInternet et download() déjà présentes.
#      - URL de base : dépôt GitHub (branche Prototype-multi-langue).
# ================================================================
checkJson() {
    local json_file="$1"
    local base_url="$url_scriptSource"
    local filename="$(basename "$json_file")"
    local url="${base_url}${filename}"

    if [[ ! -f "$json_file" ]]; then
        echoError "$(lang file_not_found): $json_file"
        if download "$url" "$json_file"; then
            echoInfo "$(lang download_ok): $url"
        else
            echoWarn "$(lang download_fail)"
            return 1
        fi
    fi
    return 0
}

# ================================================================
# loadJsonToArray
# ----------------------------------------------------------------
# EN: Load JSON content into a global array/associative array.
#     - Default "flat" mode: JSON is flattened into key=value pairs.
#     - "object" mode: Each array element (e.g. profiles[]) is stored raw.
#     - Requires jq.
# FR: Charge un JSON dans un tableau global ou un tableau associatif.
#     - Mode par défaut "flat": les clés imbriquées deviennent key=value.
#     - Mode "object": chaque élément du tableau (ex: profiles[]) est stocké brut.
#     - Nécessite jq.
# ================================================================
loadJsonToArray() {
    local functionName="loadJsonToArray"
    local json_file="$1"
    local array_name="$2"
    local mode="${3:-flat}"   # flat (default) | object
    local root_key="${4:-profiles}"  # utilisé seulement en mode object

    if ! checkJson "$json_file"; then
        return 1
    fi
    if ! jq empty "$json_file" >/dev/null 2>&1; then
        echoError "$(lang invalid_file): $json_file"
        return 1
    fi

    case "$mode" in
        flat)
            sortJsonKeys "$json_file"
            eval "declare -g -A $array_name"
            while IFS="=" read -r key value; do
                eval "$array_name[\"\$key\"]=\"\$value\""
            done < <(jq -r 'paths(scalars) as $p | "\($p | join("."))=\(getpath($p))"' "$json_file")
            ;;
        object)
            eval "unset $array_name; declare -g -a $array_name=()"
            while IFS= read -r obj; do
                eval "$array_name+=(\"\$obj\")"
            done < <(jq -c ".${root_key}[]" "$json_file")
            ;;
        *)
            echoError "$(lang Unknown_mode) : $mode"
            return 1
            ;;
    esac

    return 0
}


# ================================================================
# sortJsonKeys
# ----------------------------------------------------------------
# EN: Sort the keys of a JSON file alphabetically.
#     - Rewrites the file in-place.
#     - Requires jq.
# FR : Trie les clés d’un fichier JSON par ordre alphabétique.
#      - Réécrit le fichier en place.
#      - Nécessite jq.
# ================================================================
sortJsonKeys() {
    local json_file="$1"
    if ! checkJson "$json_file"; then
        return 1
    fi

    local tmpfile
    tmpfile=$(mktemp)
    jq -S . "$json_file" > "$tmpfile" && mv "$tmpfile" "$json_file"
}

# ================================================================
# getJsonValue
# ----------------------------------------------------------------
# EN: Get a specific value from a JSON file using a jq path.
#     - Usage: getJsonValue file.json ".lang.en"
# FR : Récupère une valeur spécifique dans un fichier JSON via jq.
#      - Exemple : getJsonValue fichier.json ".lang.fr"
# ================================================================
getJsonValue() {
    local json_file="$1"
    local key="$2"

    if ! checkJson "$json_file"; then
        return 1
    fi

    # S'assurer que la clé commence par un "."
    [[ "$key" != .* ]] && key=".$key"

    jq -r "$key" "$json_file" 2>/dev/null
}

# ================================================================
# updateJsonValue
# ----------------------------------------------------------------
# EN: Update a specific value in a JSON file.
#     - Usage: updateJsonValue file.json '.path.to.key' "new value"
#     - Requires jq.
# FR : Met à jour une valeur spécifique dans un fichier JSON.
#      - Usage : updateJsonValue fichier.json '.chemin.vers.cle' "nouvelle valeur"
#      - Nécessite jq.
# ================================================================
updateJsonValue() {
    local json_file="$1"
    local key="$2"
    local new_value="$3"

    if ! checkJson "$json_file"; then
        return 1
    fi

    local tmpfile
    tmpfile=$(mktemp)
    if jq --arg v "$new_value" "$key = \$v" "$json_file" > "$tmpfile"; then
        mv "$tmpfile" "$json_file"
        echoCheck "$(lang package_modified): $key"
    else
        echoError "$(lang error) update $key"
        rm -f "$tmpfile"
        return 1
    fi
}

# ============================================================
# checkUpdate
# ------------------------------------------------------------
# EN : Checks for available script updates.
# FR : Vérifie les mise à jour disponible du script.
# ============================================================
function checkUpdate() {
    # Déduire les URLs des JSON depuis url_script
    local url_base="${url_script%/*}/"          # base : https://raw.githubusercontent.com/.../Prototype/
    local url_version="${url_base}$VERSION_FILE"
    local url_lang="${url_base}$LANG_FILE"
    local url_tasks="${url_base}$TASKS_FILE"
    local url_profiles="${url_base}$PROFILES_FILE"

    # Vérification de la version du script
    echo "🔎 $(lang update_check)"
    local onlineVersion="$(download "$url_version")"

    if [[ -z "$onlineVersion" ]]; then
        echoWarn "$(lang unable_check_version)"
        return
    fi

    if [[ "$onlineVersion" != "$scriptVersion" ]]; then
        echoWarn "$(lang update_available) $onlineVersion (actuelle : $scriptVersion)"
        read -p "$(lang update_prompt)" rep
        if [[ "$rep" =~ ^[Oo]$ ]]; then
            echo "⬇️ $(lang downloading_new_version)..."
            download "$url_script" "$0" # Download new script
            chmod +x "$0"

            if download "$url_lang" "$LANG_FILE"; then
                echoCheck "$(lang download_ok)$LANG_FILE."
            else
                echoError "$(lang download_failed) $LANG_FILE"
            fi
            if download "$url_tasks" "$TASKS_FILE"; then
                echoCheck "$(lang download_ok)$TASKS_FILE."
            else
                echoError "$(lang download_failed) $TASKS_FILE"
            fi
            if download "$url_profiles" "$PROFILES_FILE"; then
                echoCheck "$(lang download_ok) $PROFILES_FILE"
            else
                echoError "$(lang download_failed) $PROFILES_FILE"
            fi
            echoCheck "$(lang update_done)"
            exec "$0" "$@"   # Relance automatique du script
        fi
    else
        echoCheck "$(lang update_none)"
    fi

    # Load language definitions
    loadJsonToArray "lang.json" "LANG_ARRAY"

    # Load tasks definitions
    loadJsonToArray "$TASKS_FILE" "TASKS_ARRAY"

    # Load profiles definitions
    loadJsonToArray "$PROFILES_FILE" "PROFILES_ARRAY" "object" "profiles"
}

# ============================================================
# updateSystem
# ------------------------------------------------------------
# EN : Checks for available system updates.
# FR : Vérifie les mise à jour disponible du système.
# ============================================================
function updateSystem {
    title "Mise à jour et vérification des dépendances" "=" "yellow"

    checkInternet

    if [[ "$OS_FAMILY" == "Linux" ]]; then
        echo "🔄 Mise à jour du système Linux ($OS_DISTRO $OS_VERSION)..."

        # Détecter le gestionnaire de packages disponible
        if command -v apt >/dev/null 2>&1; then
            PKG_CMD="sudo apt"
            UPDATE_CMD="update && sudo apt upgrade -y"
            INSTALL_CMD="install -y"
        elif command -v dnf >/dev/null 2>&1; then
            PKG_CMD="sudo dnf"
            UPDATE_CMD="upgrade --refresh -y"
            INSTALL_CMD="install -y"
        elif command -v pacman >/dev/null 2>&1; then
            PKG_CMD="sudo pacman"
            UPDATE_CMD="-Syu --noconfirm"
            INSTALL_CMD="-S --noconfirm"
        elif command -v zypper >/dev/null 2>&1; then
            PKG_CMD="sudo zypper"
            UPDATE_CMD="refresh && sudo zypper update -y"
            INSTALL_CMD="install -y"
        elif command -v apk >/dev/null 2>&1; then
            PKG_CMD="sudo apk"
            UPDATE_CMD="update"
            INSTALL_CMD="add"
        else
            echo "⚠️ Aucun gestionnaire de packages reconnu sur cette distribution."
        fi

        # Mise à jour du système si gestionnaire détecté
        if [[ -n "$PKG_CMD" ]]; then
            echo "🔄 Mise à jour via $PKG_CMD..."
            eval "$PKG_CMD $UPDATE_CMD"
            echo "🔧 Installation des dépendances..."
            eval "$PKG_CMD $INSTALL_CMD jq whiptail curl unzip wget dos2unix"
        fi

        # Détecter le mode GUI
        if command -v whiptail >/dev/null 2>&1; then
            GUI="menuWhiptail"
        else
            GUI="menuMain"
        fi

    elif [[ "$OS_FAMILY" == "macOS" ]]; then
        echo "🔄 Vérification du système macOS ($OS_VERSION)..."
        if ! command -v brew >/dev/null 2>&1; then
            echo "⚠️ Homebrew non trouvé, installation..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        fi
        brew update
        brew upgrade
        brew install jq wget curl
        GUI="menuMain"

    elif [[ "$OS_FAMILY" == "Windows" ]]; then
        echo "🔄 Mise à jour Windows ($OS_DISTRO $OS_VERSION)..."
        winget upgrade --all
        winget install --id MartiCliment.UniGetUI -e --accept-source-agreements --accept-package-agreements
        winget install --id jq -e --accept-source-agreements --accept-package-agreements
        GUI="menu"

    else
        echo "❌ OS non reconnu, impossible de mettre à jour et installer les dépendances."
        GUI="menu"
    fi

    echo "✅ Vérification système terminée. Mode GUI : $GUI"
}

getTaskField() {
  local task="$1"     # ex: vim
  local field="$2"    # ex: description, category
  local lang="${3:-$CURRENT_LANG}"

  # Tentative dans la langue courante
  local val="${TASKS_ARRAY[$task.$field.$lang]}"

  # Fallback en anglais
  [[ -z "$val" ]] && val="${TASKS_ARRAY[$task.$field.en]}"

  # Sinon affiche la clé brute
  [[ -z "$val" ]] && val="$field"

  printf "%s" "$val"
}

function arrayToJson() {
    local arr=("$@")
    printf '%s\n' "${arr[@]}" | jq -R . | jq -s .
}

# ============================================================
# manageTasks (corrigé avec translate)
# ------------------------------------------------------------
# EN : Manage adding, editing, or deleting tasks.
# FR : Gérer l'ajout, la modification ou la suppression de tâches.
# ============================================================

# --- Helper pour mettre à jour un champ multilingue
updateMultilangField() {
    local task="$1"
    local field="$2"   # description ou category
    local prompt="$3"  # message affiché
    local new_cur new_en

    read -r -p "$prompt " new_cur
    [[ -z "$new_cur" ]] && return 1

    # Sauvegarde dans la langue courante
    jq --arg name "$task" --arg lang "$CURRENT_LANG" --arg v "$new_cur" \
      "(.tasks[] | select(.name==\$name) | .${field}) |= ((. // {}) | .[\$lang]=\$v)" \
      "$TASKS_FILE" > "$TASKS_FILE.tmp" && mv "$TASKS_FILE.tmp" "$TASKS_FILE"

    # Traduction en anglais si nécessaire
    if [[ "$CURRENT_LANG" != "en" ]]; then
        new_en="$(translate "$new_cur" "en")"
        if [[ -n "$new_en" ]]; then
            jq --arg name "$task" --arg v "$new_en" \
              "(.tasks[] | select(.name==\$name) | .${field}) |= ((. // {}) | .en=\$v)" \
              "$TASKS_FILE" > "$TASKS_FILE.tmp" && mv "$TASKS_FILE.tmp" "$TASKS_FILE"
        fi
    fi
}

function manageTasks {
    local functionName="manageTasks"
    local task="$1"
    local action=""

    # --- Display title
    title "$(lang manage_tasks)"

    # --- If no task provided, ask user for action
    if [[ -z "$task" ]]; then
        PS3="$(lang select_action)"
        select action in "$(lang add)" "$(lang edit)" "$(lang delete)" "$(lang cancel)"; do
            case $REPLY in
                1) action="add"; break ;;
                2) action="edit"; break ;;
                3) action="delete"; break ;;
                4) return ;;
                *) echoError "$(lang invalid_choice)" ;;
            esac
        done
    else
        # If task exists, default to edit, otherwise to add
        if jq -e --arg name "$task" '.tasks[] | select(.name==$name)' "$TASKS_FILE" >/dev/null 2>&1; then
            action="edit"
        else
            action="add"
        fi
    fi

    # --- If editing or deleting, show a list of tasks
    if [[ "$action" == "edit" || "$action" == "delete" ]]; then
        mapfile -t task_list < <(jq -r '.tasks[].name' "$TASKS_FILE")
        echoInfo "📦 $(lang available_tasks):"
        select task in "${task_list[@]}" "$(lang cancel)"; do
            if [[ "$REPLY" -ge 1 && "$REPLY" -le "${#task_list[@]}" ]]; then
                break
            elif [[ "$REPLY" -eq $(( ${#task_list[@]} + 1 )) ]]; then
                return
            else
                echoError "$(lang invalid_choice)"
            fi
        done
    fi

    case $action in
        delete)
            jq --arg name "$task" 'del(.tasks[] | select(.name==$name))' "$TASKS_FILE" > "$TASKS_FILE.tmp" && mv "$TASKS_FILE.tmp" "$TASKS_FILE"
            echoCheck "🗑️ $(printf "$(lang task_deleted)" "$task")"
            ;;
        edit)
            jq --arg name "$task" '.tasks[] | select(.name==$name)' "$TASKS_FILE" | jq .
            echoInfo "✏️ $(printf "$(lang task_modified)" "$task")"

            PS3="$(lang select_field)"
            select field in "$(lang description)" "$(lang category)" "$(lang commands)" "$(lang cancel)"; do
                case $REPLY in
                    1) updateMultilangField "$task" "description" "$(lang new_description):" ;;
                    2) updateMultilangField "$task" "category" "$(lang new_category):" ;;
                    3) # commands
                        for os in linux windows macos; do
                            echoInfo "🖥️ $(printf "$(lang existing_commands)" "$os")"
                            mapfile -t current_cmds < <(jq -r --arg name "$task" --arg os "$os" \
                                '.tasks[] | select(.name==$name) | .[$os] // [] | .[]?' "$TASKS_FILE")
                            for c in "${current_cmds[@]}"; do echo " - $c"; done

                            read -r -p "$(printf "$(lang add_command)" "$os"): " cmd
                            if [[ -n "$cmd" ]]; then
                                jq --arg name "$task" --arg os "$os" --arg cmd "$cmd" \
                                    '(.tasks[] | select(.name==$name) | .[$os]) += [$cmd]' \
                                    "$TASKS_FILE" > "$TASKS_FILE.tmp" && mv "$TASKS_FILE.tmp" "$TASKS_FILE"
                            fi
                        done
                        ;;
                    4) return ;;
                    *) echoError "$(lang invalid_choice)" ;;
                esac
                jq --arg name "$task" '.tasks[] | select(.name==$name)' "$TASKS_FILE" | jq .
                echoInfo "$(lang modification_done)"
            done
            ;;
        add)
            echoInfo "➕ $(lang prompt_new_task):"
            read -r -p "$(lang name): " name
            task="$name"

            # --- Description
            read -r -p "$(lang description): " desc_cur
            desc_en="$desc_cur"
            if [[ "$CURRENT_LANG" != "en" ]]; then
                desc_en="$(translate "$desc_cur" "en")"
            fi

            # --- Category
            read -r -p "$(lang category): " cat_cur
            cat_en="$cat_cur"
            if [[ "$CURRENT_LANG" != "en" ]]; then
                cat_en="$(translate "$cat_cur" "en")"
            fi

            # --- Commands
            declare -a linux_cmds=()
            declare -a windows_cmds=()
            declare -a macos_cmds=()

            read -r -p "$(lang command_line_linux): " input
            [[ -n "$input" ]] && IFS=';' read -r -a linux_cmds <<< "$input"

            read -r -p "$(lang command_line_windows): " input
            [[ -n "$input" ]] && IFS=';' read -r -a windows_cmds <<< "$input"

            read -r -p "$(lang command_line_macos): " input
            [[ -n "$input" ]] && IFS=';' read -r -a macos_cmds <<< "$input"

            linux_json=$(arrayToJson "${linux_cmds[@]}")
            windows_json=$(arrayToJson "${windows_cmds[@]}")
            macos_json=$(arrayToJson "${macos_cmds[@]}")

            jq --arg name "$task" \
               --arg desc_cur "$desc_cur" --arg desc_en "$desc_en" \
               --arg cat_cur "$cat_cur" --arg cat_en "$cat_en" \
               --arg cur "$CURRENT_LANG" \
               --argjson linux "$linux_json" \
               --argjson windows "$windows_json" \
               --argjson macos "$macos_json" \
               '
               .tasks += [{
                 "name": $name,
                 "description": { ($cur): $desc_cur, "en": $desc_en },
                 "category": { ($cur): $cat_cur, "en": $cat_en },
                 "linux": $linux,
                 "windows": $windows,
                 "macos": $macos
               }]
               ' "$TASKS_FILE" > "$TASKS_FILE.tmp" && mv "$TASKS_FILE.tmp" "$TASKS_FILE"

            echoCheck "✅ $(printf "$(lang task_added)" "$task")"
            ;;
    esac
}

# ============================================================
# manageProfiles
# ------------------------------------------------------------
# EN : Manage adding, editing, or deleting profiles.
# FR : Gérer l'ajout, la modification ou la suppression de profils.
# ============================================================
function manageProfiles {
    local functionName="manageProfiles"
    local profile="$1"
    local action=""

    # --- Afficher le titre
    title "$(lang manage_profiles)"

    # --- Si aucun profil fourni, demander l’action
    if [[ -z "$profile" ]]; then
        PS3="$(lang select_action)"
        select action in "$(lang add)" "$(lang edit)" "$(lang delete)" "$(lang cancel)"; do
            case $REPLY in
                1) action="add"; break ;;
                2) action="edit"; break ;;
                3) action="delete"; break ;;
                4) return ;;
                *) echoError "$(lang invalid_choice)" ;;
            esac
        done
    else
        # Si le profil existe, on passe en édition, sinon en ajout
        if jq -e --arg name "$profile" '.profiles[] | select(.name==$name)' "$PROFILES_FILE" >/dev/null 2>&1; then
            action="edit"
        else
            action="add"
        fi
    fi

    # --- Si édition ou suppression, lister les profils
    if [[ "$action" == "edit" || "$action" == "delete" ]]; then
        mapfile -t profile_list < <(jq -r '.profiles[].name' "$PROFILES_FILE")
        echoInfo "📂 $(lang available_profiles):"
        select profile in "${profile_list[@]}" "$(lang cancel)"; do
            if [[ "$REPLY" -ge 1 && "$REPLY" -le "${#profile_list[@]}" ]]; then
                break
            elif [[ "$REPLY" -eq $(( ${#profile_list[@]} + 1 )) ]]; then
                return
            else
                echoError "$(lang invalid_choice)"
            fi
        done
    fi

    case $action in
        delete)
            jq --arg name "$profile" 'del(.profiles[] | select(.name==$name))' "$PROFILES_FILE" > "$PROFILES_FILE.tmp" && mv "$PROFILES_FILE.tmp" "$PROFILES_FILE"
            echoCheck "🗑️ $(printf "$(lang profile_deleted)" "$profile")"
            ;;
        edit)
            jq --arg name "$profile" '.profiles[] | select(.name==$name)' "$PROFILES_FILE" | jq .
            echoInfo "✏️ $(printf "$(lang profile_modified)" "$profile")"

            PS3="$(lang select_field)"
            select field in "$(lang description)" "$(lang tasks)" "$(lang cancel)"; do
                case $REPLY in
                    1) 
                        updateMultilangField "$profile" "description" "$(lang new_description):"
                        ;;
                    2) 
                        echoInfo "📝 $(lang current_tasks):"
                        jq -r --arg name "$profile" '.profiles[] | select(.name==$name) | .tasks[]?' "$PROFILES_FILE"

                        echoInfo "➕ $(lang available_tasks):"
                        mapfile -t task_list < <(jq -r '.tasks[].name' "$TASKS_FILE")
                        select task in "${task_list[@]}" "$(lang done)"; do
                            if [[ "$REPLY" -ge 1 && "$REPLY" -le "${#task_list[@]}" ]]; then
                                jq --arg name "$profile" --arg task "$task" \
                                   '(.profiles[] | select(.name==$name) | .tasks) += [$task] | (.tasks |= unique)' \
                                   "$PROFILES_FILE" > "$PROFILES_FILE.tmp" && mv "$PROFILES_FILE.tmp" "$PROFILES_FILE"
                                echoCheck "✅ $(printf "$(lang task_added_to_profile)" "$task" "$profile")"
                            elif [[ "$REPLY" -eq $(( ${#task_list[@]} + 1 )) ]]; then
                                break
                            else
                                echoError "$(lang invalid_choice)"
                            fi
                        done
                        ;;
                    3) return ;;
                    *) echoError "$(lang invalid_choice)" ;;
                esac
                jq --arg name "$profile" '.profiles[] | select(.name==$name)' "$PROFILES_FILE" | jq .
                echoInfo "$(lang modification_done)"
            done
            ;;
        add)
            echoInfo "➕ $(lang prompt_new_profile):"
            read -r -p "$(lang name): " name
            profile="$name"

            # --- Description
            read -r -p "$(lang description): " desc_cur
            desc_en="$desc_cur"
            if [[ "$CURRENT_LANG" != "en" ]]; then
                desc_en="$(translate "$desc_cur" "en")"
            fi

            # --- Tâches
            declare -a tasks=()
            echoInfo "➕ $(lang available_tasks):"
            mapfile -t task_list < <(jq -r '.tasks[].name' "$TASKS_FILE")
            select task in "${task_list[@]}" "$(lang done)"; do
                if [[ "$REPLY" -ge 1 && "$REPLY" -le "${#task_list[@]}" ]]; then
                    tasks+=("$task")
                elif [[ "$REPLY" -eq $(( ${#task_list[@]} + 1 )) ]]; then
                    break
                else
                    echoError "$(lang invalid_choice)"
                fi
            done

            tasks_json=$(arrayToJson "${tasks[@]}")

            jq --arg name "$profile" \
               --arg desc_cur "$desc_cur" --arg desc_en "$desc_en" \
               --arg cur "$CURRENT_LANG" \
               --argjson tasks "$tasks_json" \
               '
               .profiles += [{
                 "name": $name,
                 "description": { ($cur): $desc_cur, "en": $desc_en },
                 "tasks": $tasks
               }]
               ' "$PROFILES_FILE" > "$PROFILES_FILE.tmp" && mv "$PROFILES_FILE.tmp" "$PROFILES_FILE"

            echoCheck "✅ $(printf "$(lang profile_added)" "$profile")"
            ;;
    esac
}

# ============================================================
# installFromLink
# ------------------------------------------------------------
# EN : Installation of packages from an internet link.
# FR : Installation des paquets depuis un lien internet.
# ============================================================
function installFromLink {
    local url="$1"
    local nom="$(basename "$url")"
    local dossier_cache="$(dirname "$0")/packages/$OS_FAMILY"
    mkdir -p "$dossier_cache"
    local file="$dossier_cache/$nom"

    # Mode cache par défaut
    local CACHE_MODE="normal"
    for arg in "$@"; do
        case "$arg" in
            --force-download) CACHE_MODE="force" ;;
            --cache-only) CACHE_MODE="cache" ;;
        esac
    done

    # Vérification du file existant
    if [[ -f "$file" ]]; then
        case "$CACHE_MODE" in
            force)
                echo "🔄 $(lang downloading) $url"
                download "$url" "$file"
                ;;
            cache)
                echoCheck "$(lang using_cache)"
                ;;
            *)
                echo "📦 $(printf "$(lang already_present)" "$nom")"
                read -p "$(lang redownload_prompt)" rep
                if [[ "$rep" =~ ^[OoYy]$ ]]; then
                    download "$url" "$file"
                else
                    echo "$(lang using_cached_file)"
                fi
                ;;
        esac
    else
        download "$url" "$file"
    fi

    # Décompression automatique pour archives
    local unpack_dir="$dossier_cache/unpacked"
    mkdir -p "$unpack_dir"
    case "$file" in
        *.zip) echo "$(lang install_zip)"; unzip -o "$file" -d "$unpack_dir" ;;
        *.tar.gz|*.tgz) tar -xzf "$file" -C "$unpack_dir" ;;
        *.tar.xz) tar -xJf "$file" -C "$unpack_dir" ;;
    esac

    # Installation selon l'OS et type de file
    case "$OS_FAMILY" in
        Linux)
            if [[ "$file" =~ \.deb$ ]]; then
                echo "$(lang install_deb)"
                sudo dpkg -i "$file" 2>/dev/null || sudo apt-get install -f -y
            elif [[ "$file" =~ \.rpm$ ]]; then
                echo "$(lang install_rpm)"
                if command -v dnf >/dev/null 2>&1; then
                    sudo dnf install -y "$file" || sudo yum localinstall -y "$file"
                else
                    sudo yum localinstall -y "$file"
                fi
            elif [[ "$file" =~ \.AppImage$ ]]; then
                echo "$(lang install_appimage)"
                chmod +x "$file"
                sudo mv "$file" /usr/local/bin/
            elif [[ -x "$file" ]]; then
                bash "$file"
            fi
            ;;
        Windows)
            if [[ "$file" =~ \.exe$ ]]; then
                echo "$(lang install_exe)"
                "$file" /quiet /norestart || "$file"
            elif [[ "$file" =~ \.msi$ ]]; then
                echo "$(lang install_msi)"
                msiexec /i "$file" /quiet /norestart
            elif [[ "$file" =~ \.zip$ ]]; then
                echo "$(lang install_zip)"
                unzip -o "$file" -d "$HOME/AppData/Local/"
            fi
            ;;
        MacOS)
            if [[ "$file" =~ \.dmg$ ]]; then
                echo "$(lang install_dmg)"
                mkdir -p "$dossier_cache/mnt"
                hdiutil attach "$file" -mountpoint "$dossier_cache/mnt"
                cp -r "$dossier_cache/mnt"/*.app /Applications/
                hdiutil detach "$dossier_cache/mnt"
            elif [[ "$file" =~ \.pkg$ ]]; then
                echo "$(lang install_pkg)"
                sudo installer -pkg "$file" -target /
            elif [[ "$file" =~ \.zip$ ]]; then
                echo "$(lang install_zip)"
                unzip -o "$file" -d /Applications/
            fi
            ;;
    esac

    echoCheck "$(lang install_success) : $nom"
}

# ============================================================
# runTask
# ------------------------------------------------------------
# EN : Execute a task (package install, backup, file ops, etc.)
#      - Supports Linux, Windows, MacOS.
#      - Reads commands and URLs from JSON.
#      - If task not found: tries fallback install and adds it.
# FR : Exécute une tâche (installation de paquet, sauvegarde,
#      opérations sur fichiers, etc.)
#      - Compatible Linux, Windows, MacOS.
#      - Lit les commandes et URLs depuis le JSON.
#      - Si la tâche est inconnue : installation fallback et ajout.
# ============================================================
function runTask {
    local task="$1"

    # Vérifie si la tâche est définie dans le JSON
    local data
    data=$(jq -r --arg t "$task" '.tasks[] | select(.name==$t)' "$TASKS_FILE")

    if [[ -z "$data" ]]; then
        echo "⚠️ $(lang task_not_found): '$task'"
        echo "➡️ $(lang attempting_auto_install)..."

        case "$OS_FAMILY" in
            Linux)
                case "$OS_DISTRO" in
                    ubuntu|debian)
                        sudo apt update
                        sudo apt install -y "$task"
                        ;;
                    fedora|rhel|centos)
                        sudo dnf install -y "$task"
                        ;;
                    arch|manjaro)
                        sudo pacman -Sy --noconfirm "$task"
                        ;;
                    *)
                        echo "⚠️ $(lang unsupported_linux_distro): $OS_DISTRO"
                        return 1
                        ;;
                esac
                jq --arg name "$task" \
                   '.tasks += [{"name":$name,"description":"Ajout automatique","linux":["installation via gestionnaire"]}]' \
                   "$TASKS_FILE" > "$TASKS_FILE.tmp" && mv "$TASKS_FILE.tmp" "$TASKS_FILE"
                ;;
            Windows)
                winget install -e --id "$task"
                jq --arg name "$task" \
                   '.tasks += [{"name":$name,"description":"Ajout automatique","windows":["winget install -e --id " + $name]}]' \
                   "$TASKS_FILE" > "$TASKS_FILE.tmp" && mv "$TASKS_FILE.tmp" "$TASKS_FILE"
                ;;
            MacOS)
                brew install "$task"
                jq --arg name "$task" \
                   '.tasks += [{"name":$name,"description":"Ajout automatique","macos":["brew install " + $name]}]' \
                   "$TASKS_FILE" > "$TASKS_FILE.tmp" && mv "$TASKS_FILE.tmp" "$TASKS_FILE"
                ;;
            *)
                echo "⚠️ $(lang unsupported_os)"
                return 1
                ;;
        esac
        return 0
    fi

    title "⚙️ $(lang running_task) : $task..." "+" "yellow"

    # Récupère URL et commandes spécifiques
    local url
    local cmds=()
    case "$OS_FAMILY" in
        Linux)
            url=$(jq -r --arg t "$task" '.tasks[] | select(.name==$t) | .urls.linux // empty' "$TASKS_FILE")
            mapfile -t cmds < <(jq -r --arg t "$task" '.tasks[] | select(.name==$t) | .linux | if type=="array" then .[] else . end' "$TASKS_FILE")
            ;;
        Windows)
            url=$(jq -r --arg t "$task" '.tasks[] | select(.name==$t) | .urls.windows // empty' "$TASKS_FILE")
            mapfile -t cmds < <(jq -r --arg t "$task" '.tasks[] | select(.name==$t) | .windows | if type=="array" then .[] else . end' "$TASKS_FILE")
            ;;
        MacOS)
            url=$(jq -r --arg t "$task" '.tasks[] | select(.name==$t) | .urls.macos // empty' "$TASKS_FILE")
            mapfile -t cmds < <(jq -r --arg t "$task" '.tasks[] | select(.name==$t) | .macos | if type=="array" then .[] else . end' "$TASKS_FILE")
            ;;
    esac

    # Téléchargement si URL
    if [[ -n "$url" && "$url" != "null" ]]; then
        echo "🌍 $(lang downloading) : $url"
        installFromLink "$url"
    fi

    # Exécution des commandes spécifiques
    if ((${#cmds[@]} > 0)); then
        echo "⚙️ $(lang executing_commands)..."
        for cmd in "${cmds[@]}"; do
            echo "➡️ $cmd"
            eval "$cmd"
        done
    fi

    echoCheck "$(lang task_success)"
}

# ================================
# runProfile
# -------------------------------
# EN: Run a given profile object.
#     - Displays localized description.
#     - Executes all tasks in the profile (calls runTask).
#
# FR: Exécute un objet profil donné.
#     - Affiche la description traduite.
#     - Exécute toutes les tâches du profil (appelle runTask).
# ================================
function runProfile {
    local functionName="runProfile"
    local profileObj="$1"

    if [[ -z "$profileObj" ]]; then
        echoError "$(lang missing_argument) (profileObj)"
        return 1
    fi

    # Nom et description traduits
    local name desc
    name=$(echo "$profileObj" | jq -r --arg lang "$CURRENT_LANG" \
        '.name[$lang] // .name.en // .name.fr // "Profile"')
    desc=$(echo "$profileObj" | jq -r --arg lang "$CURRENT_LANG" \
        'if (.description | type) == "object" then
            (.description[$lang] // .description.en // .description.fr // "")
         else
            .description // ""
         end')

    echoInfo "$(lang running_profile): $name — $desc"

    # Exécuter toutes les tâches
    local tasks
    tasks=$(echo "$profileObj" | jq -r '.tasks[]?')

    if [[ -z "$tasks" ]]; then
        echoWarn "$(lang profile_empty): $name"
        return 0
    fi

    while IFS= read -r task; do
        [[ -n "$task" ]] && runTask "$task"
    done <<< "$tasks"
}


# ============================================================
# IMPORT / EXPORT
# ============================================================
# ============================================================
# IMPORT
# ============================================================
# importPackages
# ------------------------------------------------------------
# EN : Import a package profile from a JSON file.
#      - Detects minimal (names) or complete (objects) format.
#      - Unknown packages from complete JSON are added to $TASKS_FILE.
#      - Adds the profile to $PROFILES_FILE and installs packages.
#      - Enter "0" to return to previous menu.
# FR : Importer un profil de paquets depuis un fichier JSON.
#      - Détecte le format minimal (noms) ou complet (objets).
#      - Les paquets inconnus du JSON complet sont ajoutés à $TASKS_FILE.
#      - Ajoute le profil à $PROFILES_FILE et installe les paquets.
#      - Entrer "0" pour revenir au menu précédent.
# ============================================================
function importPackages {
    local file="$1"

    # --- Ask for file if not provided
    if [[ -z "$file" ]]; then
        title "$(lang select_file_import)" "-" "cyan"
        local files=($(ls "$(dirname "$0")"/*.json 2>/dev/null))
        
        if [[ ${#files[@]} -eq 0 ]]; then
            read -rp "$(lang no_json_found)" file
        else
            echo " 0) $(lang return_menu)"
            echo " 1) $(lang custom_path)"
            for i in "${!files[@]}"; do
                echo " $((i+2))) ${files[$i]}"
            done
            read -rp "$(lang choose_file)" choice
            if [[ "$choice" == "0" ]]; then
                return 0
            elif [[ "$choice" == "1" ]]; then
                read -rp "$(lang enter_full_path)" file
            elif [[ "$choice" =~ ^[0-9]+$ ]] && (( choice > 1 && choice <= ${#files[@]}+1 )); then
                file="${files[$((choice-2))]}"
            else
                echoError "$(lang invalid_choice)"
                return 1
            fi
        fi
    fi

    # --- Check file existence
    if [[ ! -f "$file" ]]; then
        echoError "$(lang file_not_found): $file"
        return 1
    fi

    # --- Detect JSON type
    local jsonType="minimal"
    local profileKey
    profileKey=$(jq -r 'keys[0]' "$file" 2>/dev/null)
    if jq -e ".\"$profileKey\"[0] | type == \"object\"" "$file" >/dev/null 2>&1; then
        jsonType="complete"
    fi

    echoInfo "📂 $(printf "$(lang import_profile)" "$profileKey" "$jsonType")"

    local packages=()
    if [[ "$jsonType" == "minimal" ]]; then
        packages=($(jq -r ".\"$profileKey\"[]" "$file"))
    else
        # Complete JSON: fetch names, add unknown packages
        mapfile -t packages < <(jq -r ".\"$profileKey\"[].name" "$file")
        for pkg in "${packages[@]}"; do
            if ! jq -e --arg name "$pkg" '.packages[] | select(.name==$name)' $TASKS_FILE >/dev/null 2>&1; then
                jq --argjson newPkg "$(jq ".\"$profileKey\"[] | select(.name==\"$pkg\")" "$file")" \
                   '.packages += [$newPkg]' $TASKS_FILE > $TASKS_FILE.tmp && mv $TASKS_FILE.tmp $TASKS_FILE
                echoCheck "➕ $(printf "$(lang added_unknown_package)" "$pkg")"
            fi
        done
    fi

    # --- Remove duplicates
    packages=($(printf "%s\n" "${packages[@]}" | sort -u))

    # --- Update $PROFILES_FILE
    jq --arg profile "$profileKey" --argjson packages "$(printf '%s\n' "${packages[@]}" | jq -R . | jq -s .)" \
       '.profiles + {($profile): $packages} | {profiles: .}' $PROFILES_FILE > $PROFILES_FILE.tmp && mv $PROFILES_FILE.tmp $PROFILES_FILE
    echoCheck "✅ $(printf "$(lang profile_added)" "$profileKey")"

    # --- Install packages
    echoInfo "📦 $(printf "$(lang installing_packages)" "${packages[*]}")"
    for pkg in "${packages[@]}"; do
        runTask "$pkg"
    done
}

# ============================================================
# EXPORT
# ============================================================
# exportPackages
# ------------------------------------------------------------
# EN : Export a package profile from JSON files.
#      - User can select existing profiles and/or extra packages.
#      - Creates minimal (names only) and complete (objects) JSON.
#      - Optionally adds the new profile to $PROFILES_FILE.
#      - Enter "0" at any prompt to return to previous menu.
# FR : Exporter un profil de paquets depuis des fichiers JSON.
#      - L’utilisateur peut sélectionner des profils et/ou des paquets supplémentaires.
#      - Génère un JSON minimal (noms) et un JSON complet (objets).
#      - Peut ajouter le profil exporté à $PROFILES_FILE.
#      - Entrer "0" pour revenir au menu précédent.
# ============================================================
function exportPackages {
    title "$(lang export_profile)" "*" "cyan"
    mergedPackages=()

    # --- Step 1 : Select existing profiles
    echo "📂 $(lang list_profiles)"
    jq -r '.profiles | keys[]' $PROFILES_FILE | nl -w2 -s". "
    read -p "👉 $(lang select_profile_prompt) (0 = $(lang return_menu)) " chosenProfiles

    if [[ "$chosenProfiles" == "0" ]]; then
        return 0
    fi

    if [[ -n "$chosenProfiles" ]]; then
        for num in $chosenProfiles; do
            profile=$(jq -r ".profiles | keys[$((num-1))]" $PROFILES_FILE)
            if [[ "$profile" != "null" ]]; then
                mapfile -t tmp < <(jq -r ".profiles.\"$profile\"[]" $PROFILES_FILE)
                mergedPackages+=("${tmp[@]}")
            fi
        done
    fi

    # --- Step 2 : Add extra packages
    echo
    echo "📦 $(lang available_packages) : "
    jq -r '.packages[].name' $TASKS_FILE | nl -w2 -s". "
    read -p "👉 $(lang choose_packages) (0 = $(lang return_menu)) " chosenPkgs

    if [[ "$chosenPkgs" == "0" ]]; then
        echoInfo "$(lang return_menu)"
        return 0
    fi

    if [[ -n "$chosenPkgs" ]]; then
        for num in $chosenPkgs; do
            package=$(jq -r ".packages[$((num-1))].name" $TASKS_FILE)
            [[ "$package" != "null" ]] && mergedPackages+=("$package")
        done
    fi

    # --- Deduplicate + sort alphabetically
    mergedPackages=($(printf "%s\n" "${mergedPackages[@]}" | sort -u))

    # --- Step 3 : Ask for new profile name
    read -p "👉 $(lang prompt_profile_name) (0 = $(lang return_menu)) " newProfile
    if [[ "$newProfile" == "0" ]]; then
        echoInfo "$(lang return_menu)"
        return 0
    fi
    [[ -z "$newProfile" ]] && newProfile="exported_profile"

    fileMinimal="$newProfile.json"
    fileComplete="$newProfile-full.json"

    # --- Minimal JSON (names only)
    jq -n --arg profile "$newProfile" \
        --argjson packages "$(printf '%s\n' "${mergedPackages[@]}" | jq -R . | jq -s .)" \
        '{($profile): $packages}' > "$fileMinimal"

    # --- Complete JSON (objects)
    namesJson=$(printf '%s\n' "${mergedPackages[@]}" | jq -R . | jq -s .)

    jq -n --arg profile "$newProfile" --argjson names "$namesJson" \
        --slurpfile allPackages $TASKS_FILE \
        '{
            ($profile): $allPackages[0].packages | map(select(.name as $n | $n | IN($names[])))
        }' > "$fileComplete"

    echoCheck "$(lang file_exported)"
    echo "   - Minimal : $fileMinimal"
    echo "   - Complete : $fileComplete"

    # --- Step 4 : Add to $PROFILES_FILE ?
    read -p "👉 $(lang promt_profile_add) (0 = $(lang return_menu)) " confirm
    if [[ "$confirm" == "0" ]]; then
        echoInfo "$(lang return_menu)"
        return 0
    fi

    if [[ "$confirm" =~ ^[oOyY]$ ]]; then
        jq --arg profile "$newProfile" \
           --argjson packages "$(printf '%s\n' "${mergedPackages[@]}" | jq -R . | jq -s .)" \
           '.profiles + {($profile): $packages} | {profiles: .}' $PROFILES_FILE \
           > $PROFILES_FILE.tmp && mv $PROFILES_FILE.tmp $PROFILES_FILE
        echoCheck "$(lang profile_added)"
    fi
}

# ================================================================
# MENUS
# ================================================================

###############################################################################
# menuSelect
# -----------------------------------------------------------------------------
# EN: Display a selection menu. Uses whiptail if available, otherwise falls back
#     to a classic text-based menu. You can force the classic mode by setting
#     the global variable FORCE_CLASSIC_MENU=1.
#
# FR: Affiche un menu de sélection. Utilise whiptail si disponible, sinon bascule
#     en mode classique texte. Vous pouvez forcer le mode classique en définissant
#     la variable globale FORCE_CLASSIC_MENU=1.
###############################################################################
menuSelect() {
  local title="$1"; shift
  local prompt="$1"; shift
  local options=("$@")
  local choice

  # Vérifier si on force le mode classique
  if [[ "$FORCE_CLASSIC_MENU" == "1" ]] || ! command -v whiptail >/dev/null 2>&1; then
    # Mode classique (texte)
    >&2 echo ""
    >&2 title "$title" "-" "cyan"
    for ((i=0; i<${#options[@]}; i++)); do
      >&2 echo "$((i+1))) ${options[$i]}"
    done
    >&2 echo "0) $(lang back)"
    >&2 echo ""

    read -rp "$prompt " choice
    echo "$choice"
  else
    # Mode whiptail
    local wtOptions=()
    for ((i=0; i<${#options[@]}; i++)); do
      wtOptions+=($((i+1)) "${options[$i]}")
    done
    wtOptions+=("0" "$(lang back)")

    choice=$(whiptail --title "$title" \
                      --menu "$prompt" 20 70 10 \
                      "${wtOptions[@]}" \
                      3>&1 1>&2 2>&3)

    echo "$choice"
  fi
}

# ============================================================
# menuMain
# ------------------------------------------------------------
# EN : Main menu of the script
# FR : Menu principal du script
# ============================================================
menuMain() {
    local functionName="${FUNCNAME}"

    while true; do
        clear
        title "$(lang "title")"

        PS3="$(lang "select_option")"
        select choice in \
            "$(lang "tasks")" \
            "$(lang "profiles")" \
            "$(lang "system")" \
            "$(lang "tools")" \
            "$(lang "about")" \
            "$(lang "exit")"; do

            case $REPLY in
                1) menuTasks ;;     # Gestion des tâches
                2) menuProfiles ;;  # Gestion des profils
                3) menuSystem ;;    # Outils système
                4) menuTools ;;     # Téléchargements & installs
                5) scriptInformation ;;
                6) return ;;        # Quitter
                *) echoError "$(lang invalid_choice)" ;;
            esac
            break
        done
    done
}

# ============================================================
# menuTasks
# ============================================================
menuTasks() {
    local functionName="${FUNCNAME}"

    title "$(lang "title")"
    PS3="$(lang "select_option")"
    select choice in \
        "$(lang "run")" \
        "$(lang "manage")" \
        "$(lang "back")"; do

        case $REPLY in
            1) runTask ;;
            2) manageTasks ;;
            3) return ;;
            *) echoError "$(lang invalid_choice)" ;;
        esac
        break
    done
}

# ============================================================
# menuProfiles
# ============================================================
menuProfiles() {
    local functionName="${FUNCNAME}"

    title "$(lang "title")"
    PS3="$(lang "select_option")"
    select choice in \
        "$(lang "run")" \
        "$(lang "manage")" \
        "$(lang "back")"; do

        case $REPLY in
            1) runProfile ;;
            2) manageProfiles ;;
            3) return ;;
            *) echoError "$(lang invalid_choice)" ;;
        esac
        break
    done
}

# ============================================================
# menuSystem
# ============================================================
menuSystem() {
    local functionName="${FUNCNAME}"

    title "$(lang "title")"
    PS3="$(lang "select_option")"
    select choice in \
        "$(lang "update_system")" \
        "$(lang "update_script")" \
        "$(lang "check_internet")" \
        "$(lang "detect_os")" \
        "$(lang "back")"; do

        case $REPLY in
            1) updateSystem ;;
            2) updateScript ;;
            3) checkInternet ;;
            4) detectOS ;;
            5) return ;;
            *) echoError "$(lang invalid_choice)" ;;
        esac
        break
    done
}

# ============================================================
# menuTools
# ============================================================
menuTools() {
    local functionName="${FUNCNAME}"

    title "$(lang "title")"
    PS3="$(lang "select_option")"
    select choice in \
        "$(lang "download")" \
        "$(lang "install_from_link")" \
        "$(lang "back")"; do

        case $REPLY in
            1) download ;;
            2) installFromLink ;;
            3) return ;;
            *) echoError "$(lang invalid_choice)" ;;
        esac
        break
    done
}

# ================================
# menuCustom
# -------------------------------
# EN: Display the list of available tasks (from tasks.json).
#     - If whiptail is available: show a multi-select checklist.
#     - Otherwise: fallback to a text menu (multiple selections with spaces).
#     - Displays description and category in the current language.
#     - Calls runTask for each selected task.
#
# FR: Affiche la liste des tâches disponibles (depuis tasks.json).
#     - Si whiptail est disponible : affiche une checklist multi-sélection.
#     - Sinon : menu texte (sélections multiples séparées par des espaces).
#     - Affiche la description et la catégorie dans la langue courante.
#     - Appelle runTask pour chaque tâche sélectionnée.
# ================================
function menuCustom {
    local functionName="${FUNCNAME}"

    if [[ ! -f "$TASKS_FILE" ]]; then
        echoError "$(lang file_not_found): $TASKS_FILE"
        return 1
    fi

    # Charger le JSON dans TASKS_ARRAY
    loadJsonToArray "$TASKS_FILE" TASKS_ARRAY

    # Extraire tous les noms de tâches
    mapfile -t taskNames < <(jq -r '.tasks[].name' "$TASKS_FILE" | sort)
    (( ${#taskNames[@]} == 0 )) && { echoError "$(lang no_tasks)"; return 1; }

    while true; do
        if [[ "$FORCE_CLASSIC_MENU" == "1" ]] || ! command -v whiptail >/dev/null 2>&1; then
            # --- Mode texte (dégradé) ---
            echo ""
            title "$(lang available_tasks)" "-" "cyan"
            for i in "${!taskNames[@]}"; do
                local taskName="${taskNames[$i]}"
                local desc category
                desc="$(getTaskField "$taskName" description)"
                category="$(getTaskField "$taskName" category)"

                if [[ -n "$category" && "$category" != "category" ]]; then
                    printf "%2d) %s : %s [%s]\n" $((i+1)) "$taskName" "$desc" "$category"
                else
                    printf "%2d) %s : %s\n" $((i+1)) "$taskName" "$desc"
                fi
            done
            echo " 0) $(lang back)"
            echo ""

            read -p "$(lang choose_tasks) " userChoice
            [[ -z "$userChoice" ]] && continue
            [[ "$userChoice" == "0" ]] && return 0

            for choice in $userChoice; do
                if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >=1 && choice <= ${#taskNames[@]} )); then
                    local idx=$((choice-1))
                    runTask "${taskNames[$idx]}"
                else
                    runTask "$choice"
                fi
            done

        else
            # --- Mode whiptail (checklist multi-sélection) ---
            local options=()
            for taskName in "${taskNames[@]}"; do
                local desc category
                desc="$(getTaskField "$taskName" description)"
                category="$(getTaskField "$taskName" category)"

                if [[ -n "$category" && "$category" != "category" ]]; then
                    options+=("$taskName" "$desc [$category]" OFF)
                else
                    options+=("$taskName" "$desc" OFF)
                fi
            done

            local choices
            choices=$(whiptail --title "$(lang available_tasks)" \
                --checklist "$(lang choose_tasks)" 20 80 12 \
                "${options[@]}" 3>&1 1>&2 2>&3)

            local exitstatus=$?
            [[ $exitstatus -ne 0 ]] && return 0   # retour ou annulation

            # Nettoyer les guillemets autour des choix renvoyés
            choices=$(echo "$choices" | tr -d '"')

            for choice in $choices; do
                runTask "$choice"
            done
        fi
    done
}

# ================================
# menuProfiles
# -------------------------------
# EN: Display available profiles, let the user select one or several,
#     then run them via runProfile.
#
# FR: Affiche les profils disponibles, permet d’en sélectionner un ou plusieurs,
#     puis les exécute avec runProfile.
# ================================
function menuProfiles2 {
      local functionName="${FUNCNAME}"

    if [[ ${#PROFILES_ARRAY[@]} -eq 0 ]]; then
        echoError "$(lang no_profiles_available)"
        return 1
    fi

    title "$(lang available_profiles)" "-" "cyan"

    local i=1
    for obj in "${PROFILES_ARRAY[@]}"; do
        local name desc
        name=$(echo "$obj" | jq -r --arg lang "$CURRENT_LANG" \
            '.name[$lang] // .name.en // .name.fr // "N/A"')
        desc=$(echo "$obj" | jq -r --arg lang "$CURRENT_LANG" \
            '.description[$lang] // .description.en // .description.fr // ""')

        echo " $i) $name : $desc"
        ((i++))
    done
    echo " 0) $(lang back)"

    echo
    read -rp "$(lang choose_profiles) " choices

    if [[ "$choices" == "0" ]]; then
        return 0
    fi

    for choice in $choices; do
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice > 0 && choice < i )); then
            local profileIndex=$((choice - 1))
            local profileObj="${PROFILES_ARRAY[$profileIndex]}"
            runProfile "$profileObj"
        else
            echoWarn "$(lang invalid_choice): $choice"
        fi
    done
}

# ================================================================
# MAIN
# ================================================================

loadLang
scriptInformation
detectOS
checkUpdate
#updateSystem
FORCE_CLASSIC_MENU=1
menuMain
