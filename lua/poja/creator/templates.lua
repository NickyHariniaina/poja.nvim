return {
  entity = [[package ${PACKAGE};

import jakarta.persistence.*;
import java.io.Serializable;
import lombok.*;

@Entity
@Table(name = "\"${TABLE}\"")
@Getter
@Setter
@Builder(toBuilder = true)
@AllArgsConstructor
@NoArgsConstructor
@SQLDelete(sql = "update \"${TABLE}\" set is_deleted = true where id = ?")
@SQLRestriction("is_deleted = false")
@EqualsAndHashCode
public class ${NAME} implements Serializable {
  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private String id;
}
]],

  controller = [[package ${PACKAGE};

import java.util.List;
import lombok.AllArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.web.bind.annotation.*;
import ${BASE_PACKAGE}.endpoint.rest.mapper.${NAME}Mapper;
import ${BASE_PACKAGE}.model.BoundedPageSize;
import ${BASE_PACKAGE}.model.PageFromOne;
import ${BASE_PACKAGE}.service.${NAME}Service;

@RestController
@AllArgsConstructor
@Slf4j
public class ${NAME}Controller {
  private final ${NAME}Service ${NAME_LOWER}Service;
  private final ${NAME}Mapper ${NAME_LOWER}Mapper;
}
]],

  service = [[package ${PACKAGE};

import jakarta.transaction.Transactional;
import java.util.List;
import lombok.AllArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import ${BASE_PACKAGE}.model.${NAME};
import ${BASE_PACKAGE}.repository.${NAME}Repository;

@Service
@AllArgsConstructor
@Slf4j
public class ${NAME}Service {
  private final ${NAME}Repository ${NAME_LOWER}Repository;
}
]],

  repository = [[package ${PACKAGE};

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;
import ${BASE_PACKAGE}.model.${NAME};

@Repository
public interface ${NAME}Repository extends JpaRepository<${NAME}, String> {
}
]],

  mapper = [[package ${PACKAGE};

import lombok.AllArgsConstructor;
import org.springframework.stereotype.Component;

@Component
@AllArgsConstructor
public class ${NAME}Mapper {
}
]],

  event = [[package ${PACKAGE};

import com.fasterxml.jackson.annotation.JsonProperty;
import java.time.Duration;
import lombok.*;
import ${BASE_PACKAGE}.endpoint.event.model.PojaEvent;

@AllArgsConstructor
@NoArgsConstructor
@EqualsAndHashCode
@Builder
@ToString
@Data
public class ${NAME}Event extends PojaEvent {
  private static final long serialVersionUID = 1L;

  @JsonProperty("data")
  private String data;

  @Override
  public Duration maxConsumerDuration() {
    return Duration.ofSeconds(60);
  }

  @Override
  public Duration maxConsumerBackoffBetweenRetries() {
    return Duration.ofSeconds(60);
  }
}
]],

  event_handler = [[package ${PACKAGE};

import java.util.function.Consumer;
import lombok.AllArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import ${BASE_PACKAGE}.endpoint.event.model.${NAME}Event;

@Service
@AllArgsConstructor
@Slf4j
public class ${NAME}Service implements Consumer<${NAME}Event> {
  @Override
  public void accept(${NAME}Event event) {
    log.info("Handling ${NAME}Event: {}", event);
  }
}
]],

  dao = [[package ${PACKAGE};

import jakarta.persistence.EntityManager;
import lombok.AllArgsConstructor;
import org.springframework.stereotype.Repository;

@Repository
@AllArgsConstructor
public class ${NAME}Dao {
  private final EntityManager entityManager;
}
]],

  validator = [[package ${PACKAGE};

import java.util.function.Consumer;
import org.springframework.stereotype.Component;
import ${BASE_PACKAGE}.model.exception.BadRequestException;

@Component
public class ${NAME}Validator implements Consumer<String> {
  @Override
  public void accept(String input) {
  }
}
]],

  exception = [[package ${PACKAGE};

import ${BASE_PACKAGE}.model.exception.ApiException;

public class ${NAME}Exception extends ApiException {
  public ${NAME}Exception(String message) {
    super(ApiException.ExceptionType.CLIENT_EXCEPTION, message);
  }
}
]],

  dto = [[package ${PACKAGE};

import java.io.Serializable;
import lombok.*;

@AllArgsConstructor
@NoArgsConstructor
@Builder
@Getter
@Setter
@EqualsAndHashCode
public class ${NAME}Dto implements Serializable {
  private String id;
}
]],
}
