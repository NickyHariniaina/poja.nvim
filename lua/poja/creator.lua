local M = {}

local templates = {
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

local types = {
  { label = "Entity",         type = "entity",         dir = "model",                  suffix = "" },
  { label = "Controller",     type = "controller",     dir = "endpoint/rest/controller", suffix = "Controller" },
  { label = "Service",        type = "service",        dir = "service",                suffix = "Service" },
  { label = "Repository",     type = "repository",     dir = "repository",             suffix = "Repository" },
  { label = "Mapper",         type = "mapper",         dir = "endpoint/rest/mapper",    suffix = "Mapper" },
  { label = "Event",          type = "event",          dir = "endpoint/event/model",    suffix = "Event" },
  { label = "Event Handler",  type = "event_handler",  dir = "service/event",           suffix = "Service" },
  { label = "DAO",            type = "dao",            dir = "repository/dao",          suffix = "Dao" },
  { label = "Validator",      type = "validator",      dir = "model/validator",         suffix = "Validator" },
  { label = "Exception",      type = "exception",      dir = "model/exception",         suffix = "Exception" },
  { label = "DTO",            type = "dto",            dir = "model/dto",               suffix = "Dto" },
}

local function camel_case(name)
  return name:sub(1,1):lower() .. name:sub(2)
end

local function snake_case(name)
  return name:gsub("([A-Z])", "_%1"):lower():gsub("^_", "")
end

local function detect_base_dir()
  local detect = require("poja.detect")
  local app_path = detect.get_poja_app_path()
  if not app_path then return nil end

  local base_dir = app_path:match("(.+/)PojaApplication%.java$")
  if base_dir then
    base_dir = base_dir:gsub("/$", "")
  end
  return base_dir
end

local function detect_base_package()
  local base_dir = detect_base_dir()
  if not base_dir then return nil end

  local java_idx = base_dir:find("src/main/java/")
  if not java_idx then return nil end

  local pkg_path = base_dir:sub(java_idx + #"src/main/java/")
  return pkg_path:gsub("/", ".")
end

local function get_target_path(entry, class_name)
  local base_dir = detect_base_dir()
  if not base_dir then return nil end

  local dir = base_dir .. "/" .. entry.dir
  local filename = class_name .. entry.suffix .. ".java"

  vim.fn.mkdir(dir, "p")
  return dir .. "/" .. filename
end

local function render_template(entry, class_name)
  local tmpl = templates[entry.type]
  if not tmpl then return nil end

  local base_package = detect_base_package()
  if not base_package then return nil end

  local sub_pkg = entry.dir:gsub("/", ".")
  local full_package = base_package .. "." .. sub_pkg

  local result = tmpl
  result = result:gsub("%${PACKAGE}", full_package)
  result = result:gsub("%${BASE_PACKAGE}", base_package)
  result = result:gsub("%${NAME}", class_name)
  result = result:gsub("%${NAME_LOWER}", camel_case(class_name))
  result = result:gsub("%${TABLE}", snake_case(class_name))

  return result
end

function M.create(type_name, class_name)
  local entry
  for _, t in ipairs(types) do
    if t.type == type_name then
      entry = t
      break
    end
  end
  if not entry then
    vim.notify("poja: unknown type '" .. type_name .. "'", vim.log.levels.ERROR)
    return
  end

  local content = render_template(entry, class_name)
  if not content then
    vim.notify("poja: not in a Poja project", vim.log.levels.WARN)
    return
  end

  local filepath = get_target_path(entry, class_name)
  if not filepath then
    vim.notify("poja: could not determine target path", vim.log.levels.ERROR)
    return
  end

  if vim.fn.filereadable(filepath) == 1 then
    vim.notify("poja: " .. filepath .. " already exists", vim.log.levels.WARN)
    return
  end

  local file = io.open(filepath, "w")
  if not file then
    vim.notify("poja: could not create " .. filepath, vim.log.levels.ERROR)
    return
  end
  file:write(content)
  file:close()

  vim.cmd("edit " .. vim.fn.fnameescape(filepath))
  vim.notify("poja: created " .. filepath, vim.log.levels.INFO)
end

function M.create_interactive()
  if not require("poja.detect").is_poja_project() then
    vim.notify("poja: not in a Poja project", vim.log.levels.WARN)
    return
  end

  vim.ui.select(types, {
    prompt = "Poja — Select type:",
    format_item = function(item)
      return item.label
    end,
  }, function(entry)
    if not entry then return end
    vim.ui.input({ prompt = "Class name: " }, function(name)
      if not name or name == "" then return end
      M.create(entry.type, name)
    end)
  end)
end

return M
