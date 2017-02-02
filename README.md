[English translation](https://github.com/PhilippeLeroux/plescripts/wiki/english)

### Objectifs :
Simuler une infrastructure de VMs pour créer des serveurs de base de données
dans les conditions proches de ce que l'on peut trouver en entreprise.

Le serveur central se nomme K2 et à en charge :
- la gestion du DNS via bind.
- la gestion du SAN via target (qui est présent sur les distributions de type Redhat),
les disques sont exportés sur le réseau via le protocole iSCSI.
- la GATEWAY qui centralise l'accès à internet des serveurs, par défaut aucun
serveur de base de données ne peut accéder à internet.
- la gestion du dépôt des rpms.

Tout type de serveurs de base de données peuvent être créé :
- Base de données sur un serveur standalone.
- Base de données en RAC (pas de RAC étendue, uniquement MAA)
- Mise en dataguard de 2 serveurs standalone.

Versions logiciels :
- Oracle Linux 7 est utilisé pour les serveurs base de données et le serveur K2.
- La version Oracle utilisée et la 12.1.0.2 (la version 12.2 n'est pas disponible
actuellement au public).

La création des serveurs de base de données est 100 % automatisée, il n'y a pas
besoins de connaissances particulières sur la gestion d'un DNS ou d'un SAN.

--------------------------------------------------------------------------------

### Étapes pour la création d'une base :

Une fois les VMs master et K2 opérationnelles, la création d'une nouvelle base
SINGLE ou RAC se fait en 5 étapes :

1. Définir l'identifiant de la base et le nombre de nœuds.

2. Clonage du serveur de référence : ~5mn par serveur.

3. Installation du Grid Infrastructure et création des DGs

	* ~35mn pour un RAC 2 nœuds.
	* ~8mn pour une SINGLE.

4. Installation d'Oracle

	* ~20mn pour un RAC 2 nœuds.
	* ~5mn pour une SINGLE.

5. Création d'une base de données CDB + 1 PDB :

	* ~30mn pour un RAC 2 nœuds.
	* ~18mn pour une SINGLE.

--------------------------------------------------------------------------------
### Télécharger les logiciels suivants :

* VirtualBox
  * Linux : zypper install [...] ou yum install [...] ou apt-get install [...] en fonction de la distribution.
	(Testé uniquement avec tumbleweed)

  * _Windows télécharger [Oracle VirtualBox](https://www.virtualbox.org/wiki/Downloads) (Windows n'est plus pris en compte pour le moment.)_

* Oracle Linux 7 : uniquement l'ISO [V100082-01.iso](https://edelivery.oracle.com/osdc/faces/SearchSoftware) est nécessaire. Rechercher Linux 7, puis décocher les autres ISO.

* [Oracle Database 12c & Grid Infrastructure 12c](http://www.oracle.com/technetwork/database/enterprise-edition/downloads/database12c-linux-download-2240591.html)

* plescripts qui doit être extrait dans $HOME.
	* Avec git : `$ git clone https://github.com/PhilippeLeroux/plescripts.git`
	* Ou télécharger le zip en cliquant sur le boutton vert "Clone or download" en haut de la page.

--------------------------------------------------------------------------------

### Création des VMs orclmaster et K2.
2 VMs sont nécessaires pour commencer : [instructions](https://github.com/PhilippeLeroux/plescripts/wiki/Création-des-VMs-orclmaster-et-K2)
 - orclmaster qui est la VM clonée dès que l'on a besoin d'un nouveau serveur Oracle
 - K2 qui est le serveur d'infrastructure (DNS, SAN, Gateway, NTP server, ...)

--------------------------------------------------------------------------------

### Création des serveurs de base de données Oracle.

* Création serveurs : [instructions](https://github.com/PhilippeLeroux/plescripts/wiki/Create-servers)

* Installation du Grid Infra & d'Oracle : [instructions](https://github.com/PhilippeLeroux/plescripts/wiki/Installation-:-Grid-infra-&-Oracle)

* Création d'une base : [instructions](https://github.com/PhilippeLeroux/plescripts/tree/master/db/README.md)

* Mise en dataguard de 2 serveurs standalones : [instructions](https://github.com/PhilippeLeroux/plescripts/wiki/Create-dataguard)

--------------------------------------------------------------------------------

##	Temps de références
### Création d'un dataguard (Base single)

script				|	id					|	temps
--------------------|:---------------------:|-------------:
clone_master.sh		|	venus				|	   3mn17s
install_grid.sh		|	venus				|	   7mn10s
install_oracle.sh	|	venus				|	   3mn46s
create_db.sh		|	venus				|	 19mn58s
clone_master.sh		|	saturne				|	   3mn40s
install_grid.sh		|	saturne				|	   7mn34s
install_oracle.sh	|	saturne				|	   4mn14s
create_dataguard.sh	|	VENUS with SATURNE	|	  11mn12s

###	Création d'un RAC

script				|	id					|	temps
--------------------|:---------------------:|-------------:
clone_master.sh		|	daisy				|	4mn15s
clone_master.sh		|	daisy				|	3mn37s
install_grid.sh		|	daisy				|	31mn46s
install_oracle.sh	|	daisy				|	13mn13s
create_db.sh		|	daisy				|	54mn29s

--------------------------------------------------------------------------------

![Screenshot](https://github.com/PhilippeLeroux/plescripts/wiki/virtualbox_manager.png)

--------------------------------------------------------------------------------

[Mes notes](https://github.com/PhilippeLeroux/plescripts/wiki)

--------------------------------------------------------------------------------

### LICENCE

Copyright © 2016,2017 Philippe Leroux <philippe.lrx@gmail.com>

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
