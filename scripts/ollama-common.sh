# Shared Ollama model helpers. Source this file from scripts in this directory.

ollama_has_model() {
	local wanted="$1"
	case "$wanted" in *:*) ;; *) wanted="$wanted:latest" ;; esac
	ollama list 2>/dev/null | awk 'NR>1{print $1}' | grep -Fqx -- "$wanted"
}
