package com.smartassembly.supervision_api;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;


/**
 * Smart Assembly Line — API de supervision
 *
 * Architecture :
 *   Edge (Greengrass) → Lambda → DynamoDB → supervision-api (ECS Fargate) → ALB
 *
 * Credentials AWS : injectés automatiquement par ECS via le Task Role
 * (pas de clé AWS dans le code ou les variables d'environnement)
 */

@SpringBootApplication
public class SupervisionApiApplication {

	public static void main(String[] args) {
		SpringApplication.run(SupervisionApiApplication.class, args);
	}

}
