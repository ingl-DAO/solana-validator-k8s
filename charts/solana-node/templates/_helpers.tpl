{{- define "solana-node.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "solana-node.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "solana-node.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "solana-node.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
solana.io/mode: {{ .Values.mode }}
{{- end }}

{{- define "solana-node.selectorLabels" -}}
app.kubernetes.io/name: {{ include "solana-node.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "solana-node.image" -}}
{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}
{{- end }}

{{- /* Guard: follower mode without hostNetwork will start, join nothing, and look healthy. */ -}}
{{- define "solana-node.validate" -}}
{{- if and (eq .Values.mode "follower") (not .Values.hostNetwork) (not .Values.validator.restrictedRepairOnly) -}}
{{- fail "mode=follower requires hostNetwork=true, because peers must reach the node at the address it advertises. The one exception is validator.restrictedRepairOnly=true, where the node deliberately does not advertise and syncs via repair instead — correct behind NAT. See docs/decisions/0005-hostnetwork-vs-nlb-vs-nodeport.md" -}}
{{- end -}}
{{- if not .Values.validator.disableXdp -}}
{{- $caps := .Values.podSecurity.capabilities.add | default list -}}
{{- if not (and (has "NET_RAW" $caps) (has "NET_ADMIN" $caps)) -}}
{{- fail "validator.disableXdp=false requires podSecurity.capabilities.add to include NET_RAW and NET_ADMIN. Agave 4.x enables XDP transmit by default and exits after binding sockets if those capabilities are absent." -}}
{{- end -}}
{{- end -}}
{{- $allowed := list "minimal" "25GB" "50GB" "100GB" "200GB" "400GB" "800GB" "unlimited" -}}
{{- if not (has (toString .Values.validator.accountsIndexLimit) $allowed) -}}
{{- fail (printf "validator.accountsIndexLimit must be one of %v, got %s. Agave rejects unknown values at startup, so this would CrashLoop." $allowed (toString .Values.validator.accountsIndexLimit)) -}}
{{- end -}}
{{- if and .Values.persistence.enabled (eq .Values.persistence.storageClassName "") -}}
{{- fail "persistence.storageClassName must be set by the infra layer — this chart never defines a StorageClass. See terraform/modules/README.md" -}}
{{- end -}}
{{- end -}}

{{- /* Cluster-specific constants. Verify known-validator pubkeys against
       docs.anza.xyz/clusters/available at build time — testnet resets change them. */ -}}
{{- define "solana-node.genesisHash" -}}
{{- if eq .Values.cluster "testnet" }}4uhcVJyU9pJkvQyS88uRDiswHXSCkY3zQawwpjk2NsNY
{{- else if eq .Values.cluster "devnet" }}EtWTRABZaYq6iMfeYKouRu166VU2xqa1wcaWoxPkrZBG
{{- else }}{{ fail (printf "unknown cluster %q" .Values.cluster) }}{{- end }}
{{- end }}
