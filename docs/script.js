const revealElements = document.querySelectorAll(".reveal");

const observer = new IntersectionObserver(
  (entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        entry.target.classList.add("in-view");
        observer.unobserve(entry.target);
      }
    });
  },
  { threshold: 0.15 }
);

revealElements.forEach((el) => observer.observe(el));

const copyButtons = document.querySelectorAll(".copy");
copyButtons.forEach((button) => {
  button.addEventListener("click", async () => {
    const code = button.closest(".code-block").querySelector("code");
    if (!code) return;

    const text = code.innerText.trim();

    try {
      await navigator.clipboard.writeText(text);
      button.textContent = "Copied";
      setTimeout(() => {
        button.textContent = "Copy";
      }, 1500);
    } catch (err) {
      button.textContent = "Copy failed";
      setTimeout(() => {
        button.textContent = "Copy";
      }, 1500);
    }
  });
});

const tabGroups = document.querySelectorAll("[data-tabs]");
tabGroups.forEach((group) => {
  const buttons = group.querySelectorAll(".tab-button");
  const panels = group.querySelectorAll("[data-tab-content]");
  const schemaLabel = group.querySelector("[data-schema-label]");

  buttons.forEach((button) => {
    button.addEventListener("click", () => {
      const target = button.dataset.tab;
      if (!target) return;

      buttons.forEach((btn) => btn.classList.remove("active"));
      button.classList.add("active");

      panels.forEach((panel) => {
        panel.classList.toggle(
          "hidden",
          panel.dataset.tabContent !== target
        );
      });

      if (schemaLabel) {
        schemaLabel.textContent =
          target === "yaml" ? "schema.yaml" : "schema.json";
      }
    });
  });
});

const terminal = document.querySelector("[data-terminal]");
if (terminal) {
  const output = terminal.querySelector(".terminal-output");
  const prefersReducedMotion = window.matchMedia(
    "(prefers-reduced-motion: reduce)"
  ).matches;

  const terminalScripts = {
    schema: [
      { type: "prompt", text: "$ cat schema.json", pause: 200 },
      { type: "output", text: "{", pause: 0 },
      { type: "output", text: "  \"type\": \"object\",", pause: 0 },
      { type: "output", text: "  \"properties\": {", pause: 0 },
      {
        type: "output",
        text: "    \"db\": {",
        pause: 0,
      },
      {
        type: "output",
        text: "      \"type\": \"object\",",
        pause: 0,
      },
      {
        type: "output",
        text: "      \"properties\": {",
        pause: 0,
      },
      {
        type: "output",
        text: "        \"host\": {\"type\": \"string\", \"default\": \"localhost\", \"description\": \"Database server\"},",
        pause: 0,
      },
      {
        type: "output",
        text: "        \"port\": {\"type\": \"integer\", \"default\": 5432, \"description\": \"Connection port\"}",
        pause: 0,
      },
      { type: "output", text: "      }", pause: 0 },
      { type: "output", text: "    },", pause: 0 },
      {
        type: "output",
        text: "    \"mode\": {\"type\": \"string\", \"enum\": [\"primary\", \"replica\"]},",
        pause: 0,
      },
      {
        type: "output",
        text: "    \"verbose\": {\"type\": \"boolean\", \"short\": \"v\"}",
        pause: 0,
      },
      { type: "output", text: "  },", pause: 0 },
      { type: "output", text: "}", pause: 350 },
    ],
    crystal: [
      { type: "prompt", text: "$ cat mycmd.cr", pause: 200 },
      { type: "output", text: "require \"jargon\"", pause: 0 },
      { type: "output", text: "", pause: 0 },
      { type: "output", text: "cli = Jargon.cli(\"mycmd\", file: \"./schema.json\")", pause: 0 },
      { type: "output", text: "res = cli.parse(ARGV)", pause: 0 },
      { type: "output", text: "", pause: 0 },
      { type: "output", text: "", pause: 0 },
      { type: "output", text: "if res.help?", pause: 0 },
      { type: "output", text: "  puts cli.help", pause: 0 },
      { type: "output", text: "elsif res.valid?", pause: 0 },
      { type: "output", text: "  puts res.to_pretty_json", pause: 0 },
      { type: "output", text: "else", pause: 0 },
      { type: "output", text: "  STDERR.puts res.errors.join(\"\\n\")", pause: 0 },
      { type: "output", text: "  exit 1", pause: 0 },
      { type: "output", text: "end", pause: 350 },
    ],
    help: [
      { type: "prompt", text: "$ mycmd --help", pause: 250 },
      { type: "output", text: "Usage: mycmd [options]", pause: 0 },
      { type: "output", text: "", pause: 0 },
      { type: "output", text: "Options:", pause: 0 },
      {
        type: "output",
        text: "  --db.host=<string>   [default: localhost]  Database server",
        pause: 0,
      },
      {
        type: "output",
        text: "  --db.port=<integer>  [default: 5432]       Connection port",
        pause: 0,
      },
      {
        type: "output",
        text: "  --mode=<string>      one of primary, replica",
        pause: 0,
      },
      {
        type: "output",
        text: "  -v, --verbose        Enable verbose logging",
        pause: 0,
      },
      { type: "output", text: "  -h, --help           Show this help", pause: 350 },
    ],
    run: [
      {
        type: "prompt",
        text: "$ mycmd mode=primary db.host=db.local verbose=true",
        pause: 250,
      },
      { type: "output", text: "{", pause: 0 },
      { type: "output", text: "  \"db\": {", pause: 0 },
      { type: "output", text: "    \"host\": \"db.local\",", pause: 0 },
      { type: "output", text: "    \"port\": 5432", pause: 0 },
      { type: "output", text: "  },", pause: 0 },
      { type: "output", text: "  \"mode\": \"primary\",", pause: 0 },
      { type: "output", text: "  \"verbose\": true", pause: 0 },
      { type: "output", text: "}", pause: 350 },
    ],
    validation: [
      { type: "prompt", text: "$ mycmd db.port=abc", pause: 250 },
      {
        type: "output",
        text: "Error: Invalid integer value 'abc' for db.port",
        pause: 350,
      },
      { type: "prompt", text: "$ mycmd --mode turbo", pause: 250 },
      {
        type: "output",
        text: "Error: Invalid value for mode: must be one of \"primary\", \"replica\"",
        pause: 350,
      },
    ],
    arguments: [
      {
        type: "prompt",
        text: "$ mycmd --db.host db.local --db.port 5432 --mode primary",
        pause: 250,
      },
      { type: "output", text: "{", pause: 0 },
      { type: "output", text: "  \"db\": {", pause: 0 },
      { type: "output", text: "    \"host\": \"db.local\",", pause: 0 },
      { type: "output", text: "    \"port\": 5432", pause: 0 },
      { type: "output", text: "  },", pause: 0 },
      { type: "output", text: "  \"mode\": \"primary\"", pause: 0 },
      { type: "output", text: "}", pause: 500 },
      {
        type: "prompt",
        text: "$ mycmd db.host=db.local db.port=5432 mode=primary",
        pause: 250,
      },
      { type: "output", text: "{", pause: 0 },
      { type: "output", text: "  \"db\": {", pause: 0 },
      { type: "output", text: "    \"host\": \"db.local\",", pause: 0 },
      { type: "output", text: "    \"port\": 5432", pause: 0 },
      { type: "output", text: "  },", pause: 0 },
      { type: "output", text: "  \"mode\": \"primary\"", pause: 0 },
      { type: "output", text: "}", pause: 350 },
      {
        type: "prompt",
        text: "$ mycmd db.host=db.local db.port=5432 mode=replica",
        pause: 250,
      },
      { type: "output", text: "{", pause: 0 },
      { type: "output", text: "  \"db\": {", pause: 0 },
      { type: "output", text: "    \"host\": \"db.local\",", pause: 0 },
      { type: "output", text: "    \"port\": 5432", pause: 0 },
      { type: "output", text: "  },", pause: 0 },
      { type: "output", text: "  \"mode\": \"replica\"", pause: 0 },
      { type: "output", text: "}", pause: 350 },
    ],
  };

  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

  let runToken = 0;

  const addCursorLine = () => {
    removeCursor();
    const cursorLine = document.createElement("div");
    cursorLine.className = "terminal-line";
    const cursor = document.createElement("span");
    cursor.className = "terminal-cursor";
    cursor.textContent = "█";
    cursorLine.appendChild(cursor);
    output.appendChild(cursorLine);
  };

  const removeCursor = () => {
    output.querySelectorAll(".terminal-cursor").forEach((cursor) => {
      if (cursor.parentElement) {
        cursor.parentElement.remove();
      }
    });
  };

  const clearOutput = () => {
    output.innerHTML = "";
  };

  const appendLine = (text, type) => {
    const line = document.createElement("div");
    line.className = `terminal-line ${type}`;
    line.textContent = text;
    output.appendChild(line);
  };

  const typeLine = async (text, type, speed) => {
    const line = document.createElement("div");
    line.className = `terminal-line ${type}`;
    output.appendChild(line);
    for (let i = 0; i < text.length; i += 1) {
      line.textContent += text[i];
      await sleep(speed);
    }
  };

  const runDemo = async (scriptKey) => {
    runToken += 1;
    const token = runToken;
    terminal.dataset.played = "true";
    clearOutput();
    const script = terminalScripts[scriptKey] || terminalScripts.schema;

    if (prefersReducedMotion) {
      script.forEach((step) => appendLine(step.text, step.type));
      addCursorLine();
      return;
    }

    for (const step of script) {
      if (token !== runToken) return;
      removeCursor();
      const speed = step.type === "prompt" ? 18 : 10;
      await typeLine(step.text, step.type, speed);
      if (step.pause) {
        await sleep(step.pause);
      }
      if (token !== runToken) return;
      addCursorLine();
    }
  };

  const demoObserver = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          if (!terminal.dataset.played) {
            const defaultScript =
              terminal.dataset.defaultScript || "crystal";
            runDemo(defaultScript);
          }
        }
      });
    },
    { threshold: 0.4 }
  );

  demoObserver.observe(terminal);

  const scriptButtons = document.querySelectorAll("[data-terminal-script]");
  scriptButtons.forEach((button) => {
    button.addEventListener("click", () => {
      const scriptKey = button.dataset.terminalScript;
      if (!scriptKey) return;

      scriptButtons.forEach((btn) => btn.classList.remove("active"));
      button.classList.add("active");

      runDemo(scriptKey);
    });
  });
}
