DROP SCHEMA IF EXISTS projetSQL CASCADE;
CREATE SCHEMA projetSQL;

CREATE SEQUENCE projetSQL.utilisateur_id;
CREATE SEQUENCE projetSQL.objet_id;
CREATE SEQUENCE projetSQL.transaction_id;
CREATE SEQUENCE projetSQL.enchere_id;
CREATE SEQUENCE projetSQL.evaluation_id;

CREATE TABLE projetSQL.utilisateurs(
	utilisateur_id integer PRIMARY KEY DEFAULT NEXTVAL('projetSQL.utilisateur_id'),
	nom varchar (25) NOT NULL CHECK (nom<>''),
	prenom varchar (25) NOT NULL CHECK (prenom<>''),
	email varchar (100) NOT NULL CHECK (email SIMILAR TO '[a-z0-9._-]+@[a-z0-9._-]{2,}.[a-z]{2,4}'),
	nom_utilisateur varchar (25) NOT NULL CHECK (nom_utilisateur<>''),
	mdp varchar (25) NOT NULL CHECK (mdp<>''),
	etat char NOT NULL CHECK (etat IN ('V','S','D')),
	moyenne double precision NOT NULL CHECK (moyenne BETWEEN 0 AND 5) DEFAULT 0,
	dernier_evaluation boolean NOT NULL DEFAULT false, 
	nb_evaluation integer NOT NULL DEFAULT 0,
	sel varchar(10) NOT NULL CHECK (sel<>''),
	nb_vente integer NOT NULL DEFAULT 0
);

CREATE TABLE projetSQL.objets(
	objet_id integer PRIMARY KEY DEFAULT NEXTVAL('projetSQL.objet_id'),
	description varchar (250) NOT NULL CHECK (description<>''),
	prix_depart double precision NOT NULL CHECK(prix_depart>=0),
	date_expiration DATE NOT NULL DEFAULT now()+ INTERVAL '15 day',
	etat char NOT NULL CHECK(etat IN ('R','E','V')) DEFAULT 'E',
	vendeur integer NOT NULL REFERENCES projetSQL.utilisateurs(utilisateur_id),
	date_mise_vente DATE NOT NULL DEFAULT now()
);

CREATE TABLE projetSQL.encheres(
	enchere_id integer PRIMARY KEY DEFAULT NEXTVAL('projetSQL.enchere_id'),
	objet_id integer NOT NULL REFERENCES projetSQL.objets(objet_id),
	prix double precision NOT NULL CHECK(prix>=0),
	etat char NULL CHECK(etat IN ('R','A','P')), -- ou E au lieu de P
	encherisseur integer NOT NULL REFERENCES projetSQL.utilisateurs(utilisateur_id),
	date_enchere DATE NOT NULL DEFAULT now()
);

CREATE TABLE projetSQL.transactions(
	transaction_id integer NOT NULL PRIMARY KEY DEFAULT NEXTVAL('projetSQL.transaction_id'),
	enchere integer NOT NULL REFERENCES projetSQL.encheres(enchere_id)
);

CREATE TABLE projetSQL.evaluations(
	evaluation_id integer PRIMARY KEY DEFAULT NEXTVAL('projetSQL.evaluation_id'),
	note integer NOT NULL CHECK(note IN(1,2,3,4,5)),
	commentaire varchar(250) CHECK (commentaire<>''),
	destinataire integer NOT NULL,
	date_evaluation DATE NOT NULL DEFAULT now(),
	utilisateur_id INTEGER NOT NULL,
	transaction_id INTEGER NOT NULL,
	FOREIGN KEY(utilisateur_id) REFERENCES projetSQL.utilisateurs(utilisateur_id),
	FOREIGN KEY(transaction_id) REFERENCES projetSQL.transactions(transaction_id),
	FOREIGN KEY(destinataire) REFERENCES projetSQL.utilisateurs(utilisateur_id)
);

--! insère un objet avec une date personnalisé --!
CREATE OR REPLACE FUNCTION 
projetSQL.insererObjet(VARCHAR(250),double precision,Date,INTEGER) RETURNS INTEGER AS $$
DECLARE
	description_objet ALIAS FOR $1;
	prix_depart_objet ALIAS FOR $2;
	date_expiration_objet ALIAS FOR $3;
	vendeur_objet ALIAS FOR $4;
	id INTEGER:=0;

BEGIN
	
	INSERT INTO projetSQL.objets VALUES 
		(DEFAULT,description_objet,prix_depart_objet,date_expiration_objet,DEFAULT,vendeur_objet,DEFAULT) 
			RETURNING objet_id INTO id;
	RETURN id;
END;
$$ LANGUAGE plpgsql;

--! création du trigger pour lever une erreur lorsque l'état de l'utilisateur est invalide et qu'il veut faire quelque chose 
CREATE OR REPLACE FUNCTION projetSQL.trigger_etat() RETURNS TRIGGER AS $$
DECLARE
	etat_utilisateur char;
BEGIN
	SELECT u.etat FROM projetSQL.utilisateurs u
			WHERE u.utilisateur_id=NEW.vendeur  INTO etat_utilisateur;
	IF (etat_utilisateur!='V') THEN RAISE 'compte utilisateur suspendu ou desactive'; 
	END IF;
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

--! trigger déclenché à cette update ou insert sur un objet 
CREATE TRIGGER trigger_etat_valide BEFORE INSERT OR UPDATE ON projetSQl.objets
FOR EACH ROW EXECUTE PROCEDURE projetSQL.trigger_etat();

--! création du trigger pour lever une erreur lorsque l'état de l'utilisateur est invalide et qu'il veut faire quelque chose 
CREATE OR REPLACE FUNCTION projetSQL.trigger_etat_encherisseur() RETURNS TRIGGER AS $$
DECLARE
	etat_utilisateur char;
BEGIN
	SELECT u.etat FROM projetSQL.utilisateurs u, projetSQL.encheres e, projetSQL.objets o
			WHERE  e.objet_id = o.objet_id
			AND o.vendeur = u.utilisateur_id INTO etat_utilisateur;
	IF (etat_utilisateur!='V') THEN RAISE 'compte utilisateur suspendu ou desactive'; 
	END IF;
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_etat_encherisseur_valide BEFORE INSERT OR UPDATE ON projetSQl.encheres
FOR EACH ROW EXECUTE PROCEDURE projetSQL.trigger_etat_encherisseur();

		
--! update d'un objet
CREATE OR REPLACE FUNCTION 
projetSQL.updateObjet(INTEGER,VARCHAR(250),double precision,Date) RETURNS INTEGER AS $$
DECLARE
	objet ALIAS FOR $1;
	description_objet ALIAS FOR $2;
	prix_depart_objet ALIAS FOR $3;
	date_expiration_objet ALIAS FOR $4;
	id INTEGER:=0;

BEGIN
	UPDATE projetSQL.objets 
			SET description=description_objet, prix_depart=prix_depart_objet,date_expiration=date_expiration_objet
			WHERE objet_id=objet 
			RETURNING objet_id INTO id;
	RETURN id;
END;
$$ LANGUAGE plpgsql;

--! liste tout les objets dont l état est en vente
CREATE OR REPLACE VIEW projetSQL.listerObjetEnVente AS 
	SELECT objet_id,description,prix_depart,date_expiration,etat,vendeur,date_mise_vente
	FROM projetSQL.objets
	WHERE etat='E';

--! création du trigger pour lever une erreur lorsque l état de l objet est invalide et qu il veut faire quelque chose 
CREATE OR REPLACE FUNCTION projetSQL.trigger_etat_objet() RETURNS TRIGGER AS $$
DECLARE
	etat_objet char;
BEGIN
	SELECT o.etat FROM projetSQL.objets o
			WHERE o.objet_id=NEW.objet_id 
			AND o.date_expiration > now() INTO etat_objet;
	IF (etat_objet!='E') THEN RAISE 'objet invalide'; 
	END IF;
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

--! trigger déclenché à cette update ou insert sur un objet 
CREATE TRIGGER trigger_etat_valide_objet AFTER INSERT OR UPDATE ON projetSQl.objets
FOR EACH ROW EXECUTE PROCEDURE projetSQL.trigger_etat_objet();

--! fait une enchère
CREATE OR REPLACE FUNCTION 
projetSQL.insererEnchere(INTEGER,double precision,INTEGER) RETURNS INTEGER AS $$
DECLARE
	objet ALIAS FOR $1;
	prix_enchere ALIAS FOR $2;
	acheteur_enchere ALIAS FOR $3;
	id INTEGER:=0;
	

BEGIN
	INSERT INTO projetSQL.encheres (enchere_id, objet_id, prix, etat,encherisseur, date_enchere)VALUES
		(DEFAULT,objet,prix_enchere,NULL,acheteur_enchere,DEFAULT) 
			RETURNING enchere_id INTO id;
	RETURN id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION projetSQL.trigger_prix_enchere() RETURNS TRIGGER AS $$
DECLARE
	prix_enchere double precision;
BEGIN
	IF EXISTS (SELECT * FROM projetSQL.encheres e 
		WHERE e.objet_id = NEW.objet_id 
		AND e.prix>=NEW.prix)
	THEN RAISE ' prix invalide '; 
	END IF;
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

--! trigger déclenché à cette update ou insert sur un objet 
CREATE TRIGGER trigger_prix_valide_encheres BEFORE INSERT ON projetSQl.encheres
FOR EACH ROW EXECUTE PROCEDURE projetSQL.trigger_prix_enchere();

--! effectue une transaction
CREATE OR REPLACE FUNCTION
projetSQL.insererTransaction(INTEGER) RETURNS INTEGER AS $$
DECLARE 
	enchere_transaction ALIAS FOR $1;
	id INTEGER:=0;
BEGIN
	
	INSERT INTO projetSQL.transactions VALUES
		(DEFAULT,enchere_transaction) 
			RETURNING transaction_id INTO id;
	RETURN id;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION projetSQL.trigger_date_expiration() RETURNS TRIGGER AS $$
DECLARE
BEGIN
	IF NOT EXISTS( SELECT o.date_expiration FROM projetSQL.encheres e,projetSQL.objets o,projetSQL.transactions t
			WHERE t.enchere=e.enchere_id
			AND e.objet_id=o.objet_id
			AND o.date_expiration<= now())
		THEN RAISE 'les enchères ne sont pas encore fini';
	END IF;
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

--! trigger déclenché à cette update ou insert sur un objet 
CREATE TRIGGER trigger_date_expire AFTER INSERT ON projetSQl.transactions
FOR EACH ROW EXECUTE PROCEDURE projetSQL.trigger_date_expiration();

CREATE OR REPLACE FUNCTION projetSQL.trigger_date_expiration_enchere() RETURNS TRIGGER AS $$
DECLARE
BEGIN
	IF NOT EXISTS( SELECT o.date_expiration FROM projetSQL.encheres e,projetSQL.objets o
			WHERE e.objet_id=o.objet_id
			AND o.date_expiration> now())
		THEN RAISE 'les enchères sont fini';
	END IF;
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

--! trigger déclenché à cette update ou insert sur un objet 
CREATE TRIGGER trigger_date_expire_enchere AFTER INSERT ON projetSQl.encheres
FOR EACH ROW EXECUTE PROCEDURE projetSQL.trigger_date_expiration_enchere();


CREATE OR REPLACE FUNCTION projetSQL.trigger_vente_expire() RETURNS TRIGGER AS $$
DECLARE
	enchere_gagnante INTEGER;
	prix_enchere double precision;
BEGIN
	SELECT max(e.prix) FROM projetSQL.encheres e INTO prix_enchere;
	
	SELECT e.enchere_id FROM projetSQL.encheres e,projetSQL.objets o
			WHERE o.objet_id=e.objet_id
			AND o.date_expiration <= now()
			AND e.prix=prix_enchere INTO enchere_gagnante;
			
	UPDATE projetSQL.encheres
		SET etat='R'
		WHERE enchere_id=enchere_gagnante;
		
	UPDATE projetSQL.encheres
		SET etat='P'
		WHERE enchere_id != enchere_gagnante;
	
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_etat_vente_expire AFTER INSERT ON projetSQL.transactions 
FOR EACH ROW EXECUTE PROCEDURE projetSQL.trigger_vente_expire();

CREATE OR REPLACE FUNCTION projetSQL.trigger_vente_expire_objet() RETURNS TRIGGER AS $$
DECLARE
	objet INTEGER;
BEGIN
	SELECT o.objet_id FROM projetSQL.objets o, projetSQL.encheres e, projetSQL.transactions t 
			WHERE  t.transaction_id=NEW.transaction_id 
			AND t.enchere = e.enchere_id 
			AND e.objet_id = o.objet_id INTO objet;
			
	UPDATE projetSQL.objets
		SET etat='V'
		WHERE objet_id=objet;
		
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

--! trigger déclenché à cette update ou insert sur un objet 
CREATE TRIGGER trigger_etat_vente_expire_objet AFTER INSERT ON projetSQL.transactions
FOR EACH ROW EXECUTE PROCEDURE projetSQL.trigger_vente_expire_objet();


CREATE OR REPLACE FUNCTION projetSQL.trigger_nb_vente() RETURNS TRIGGER AS $$
DECLARE
	vendeur_objet INTEGER;
BEGIN
	SELECT o.vendeur FROM projetSQL.transactions t,projetSQL.objets o,projetSQL.encheres e
			WHERE t.enchere=e.enchere_id
			AND e.objet_id=o.objet_id INTO vendeur_objet; 
	UPDATE projetSQL.utilisateurs
		SET nb_vente=nb_vente+1
		WHERE utilisateur_id=vendeur_objet;
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

--! trigger déclenché à cette update ou insert sur un objet 
CREATE TRIGGER trigger_nb_vente_utilisateur AFTER INSERT ON projetSQl.transactions
FOR EACH ROW EXECUTE PROCEDURE projetSQL.trigger_nb_vente();

--! insère une evaluation
CREATE OR REPLACE FUNCTION
projetSQL.insererEvaluations(INTEGER,INTEGER,INTEGER,VARCHAR(250),INTEGER) RETURNS BOOLEAN AS $$
DECLARE 
	utilisateur_evaluation ALIAS FOR $1;
	transaction_evaluation ALIAS FOR $2;
	note_evaluation ALIAS FOR $3;
	commentaire_evaluation ALIAS FOR $4;
	destinataire_evaluation ALIAS FOR $5;
	id INTEGER:=0;
BEGIN
	INSERT INTO projetSQL.evaluations VALUES
		(DEFAULT,note_evaluation,commentaire_evaluation,destinataire_evaluation,DEFAULT,utilisateur_evaluation,transaction_evaluation); 
			
	RETURN true;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION projetSQL.trigger_nb_evaluation() RETURNS TRIGGER AS $$
DECLARE
	note_eval INTEGER;
	destinataire_eval INTEGER;
	moyenne_eval double precision;
BEGIN
	SELECT u.utilisateur_id FROM projetSQL.evaluations e,projetSQL.utilisateurs u
			WHERE u.utilisateur_id=e.destinataire INTO destinataire_eval; 
	UPDATE projetSQL.utilisateurs
		SET nb_evaluation=nb_evaluation+1
		WHERE utilisateur_id=destinataire_eval;

	SELECT avg(e.note),e.destinataire FROM projetSQL.evaluations e,projetSQL.utilisateurs u
			WHERE u.utilisateur_id=e.destinataire 
			GROUP BY e.destinataire INTO moyenne_eval,destinataire_eval; 
	UPDATE projetSQL.utilisateurs
		SET moyenne=moyenne_eval
		WHERE utilisateur_id=destinataire_eval;
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

--! trigger déclenché à cette update ou insert sur un objet 
CREATE TRIGGER trigger_nb_evaluation AFTER INSERT ON projetSQl.evaluations
FOR EACH ROW EXECUTE PROCEDURE projetSQL.trigger_nb_evaluation();








INSERT INTO projetSQL.utilisateurs(utilisateur_id,nom,prenom,email,nom_utilisateur,mdp,etat,moyenne,dernier_evaluation,nb_evaluation,sel,nb_vente)
VALUES (DEFAULT,'Bertolini','Nicolas','nicolas.bertolini@student.vinci.be','nBerto','test','V',0,DEFAULT,0,'sel',0);

INSERT INTO projetSQL.utilisateurs(utilisateur_id,nom,prenom,email,nom_utilisateur,mdp,etat,moyenne,dernier_evaluation,nb_evaluation,sel,nb_vente)
VALUES (DEFAULT,'Jager','Eren','eren.jager@student.vinci.be','Jager','test','V',0,DEFAULT,0,'sel',0);


INSERT INTO projetSQL.utilisateurs(utilisateur_id,nom,prenom,email,nom_utilisateur,mdp,etat,moyenne,dernier_evaluation,nb_evaluation,sel,nb_vente)
VALUES (DEFAULT,'Ackerman','Levi','levi.ackerman@student.vinci.be','lAckerm','test','S',0,DEFAULT,0,'sel',0);
SELECT projetSQL.insererObjet('pokemon',35,(NOW() - interval '4 days')::Date,1);
SELECT projetSQL.updateObjet(1,'pokemon silver',10.50,(NOW()+interval '4 days')::Date);
SELECT * FROM projetSQL.listerObjetEnVente;
SELECT projetSQL.insererEnchere(1,11,2);
SELECT projetSQL.insererEnchere(1,12,2);
SELECT projetSQL.insererEnchere(1,13,2);
SELECT * FROM projetSQL.encheres;
SELECT projetSQL.updateObjet(1,'pokemon silver',10.50,(NOW()-interval '4 days')::Date);
SELECT projetSQL.insererTransaction(3);
SELECT * FROM projetSQL.transactions;
SELECT projetSQL.insererEvaluations(2,1,5,'c etait bien',1);
SELECT * FROM projetSQL.utilisateurs;
SELECT * FROM projetSQL.encheres;
SELECT * FROM projetSQL.objets;

