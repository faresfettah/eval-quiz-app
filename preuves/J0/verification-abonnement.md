# J0 — Vérification de l'abonnement Azure

**Date :** 17/11/2026
**Outil :** Azure CLI 2.90.0

Les identifiants d'abonnement et d'annuaire (tenant) ont été volontairement retirés de ce document.

## 1. Compte et abonnement

| Élément | Valeur |
|---|---|
| Annuaire (tenant) | Compte de l'école |
| Abonnement | **Azure for Students**, état `Enabled` |

**Incident rencontré :** après le premier `az login`, la CLI affichait `N/A (tenant level account)`. Le compte de l'école était bien reconnu, mais aucun abonnement n'y était rattaché, et il était donc impossible de créer des ressources.
**Résolution :** j'ai activé l'offre Azure for Students sur https://azure.microsoft.com/free/students/, puis rafraîchi la liste avec `az account list --refresh`.

## 2. Stratégie (policy) appliquée

```text
Allowed resource deployment regions
listOfAllowedLocations : spaincentral, germanywestcentral, denmarkeast, austriaeast, francecentral
```

Toute création de ressource en dehors de ces 5 régions est refusée.

## 3. Disponibilité des services dans les régions autorisées

| Service | France Central | Germany West Central | Spain Central | Austria East | Denmark East |
|---|---|---|---|---|---|
| Container Apps (`managedEnvironments`, `containerApps`) | OK | OK | OK | OK | **absent** |
| Container Registry (`registries`) | OK | OK | OK | OK | OK |
| Log Analytics (`workspaces`) | OK | OK | OK | OK | OK |

**Choix : `francecentral`.** La région est autorisée, propose tous les services nécessaires, et c'est la plus proche des utilisateurs (latence). Pour la base Neon (J5), on choisira aussi une région européenne proche.

## 4. Fournisseurs de ressources

| Fournisseur | Avant | Après `az provider register` |
|---|---|---|
| Microsoft.App (Container Apps) | NotRegistered | **Registered** |
| Microsoft.ContainerRegistry (ACR) | NotRegistered | **Registered** |
| Microsoft.OperationalInsights (Log Analytics) | NotRegistered | **Registered** |

## 5. Quotas Container Apps (France Central)

| Quota | Utilisé | Limite |
|---|---|---|
| Managed Environment Count | 0 | **1** |
| Sandbox Cores | 0 | 10 |

**Restriction importante :** l'abonnement autorise **un seul environnement Container Apps** dans la région. Il suffit pour le projet (frontend et backend partagent le même environnement), mais l'ancien environnement doit être supprimé (`scripts/destroy.sh`) avant d'en recréer un.

## 6. Coûts anticipés (crédit Azure for Students)

| Ressource | Modèle de coût | Décision |
|---|---|---|
| ACR SKU **Basic** | Facturé à la journée, environ 0,17 $/jour | Créé seulement au J3 et supprimé avec `destroy.sh` quand il n'est plus nécessaire |
| Container Apps, plan **Consumption** | Enveloppe gratuite mensuelle (vCPU-secondes, Gio-secondes, requêtes) | Réplicas minimaux, scale-to-zero possible |
| Log Analytics | Facturé à l'ingestion des logs | Volume très faible pour l'exercice ; à surveiller |

Le crédit restant se consulte dans le portail Azure, à la page **Education** (vue d'ensemble).

## 7. Commandes utilisées

```bash
az login
az account list --refresh --query "[].{nom:name, etat:state}" -o table
az policy assignment list --disable-scope-strict-match --query "[].displayName" -o table
az provider show -n Microsoft.App --query "resourceTypes[?resourceType=='managedEnvironments'].locations[]" -o tsv
az provider register --namespace Microsoft.App --wait
az provider register --namespace Microsoft.ContainerRegistry --wait
az provider register --namespace Microsoft.OperationalInsights --wait
az rest --method get --url "https://management.azure.com/subscriptions/<id>/providers/Microsoft.App/locations/francecentral/usages?api-version=2024-03-01"
```
