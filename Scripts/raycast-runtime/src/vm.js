// No second realm: a context is its own sandbox, read and written through a `with` over a Proxy.

const intrinsicEval = eval;
const contexts = new WeakSet();

// The evaluator's own parameter names must stay out of the `with`, or it would swallow `code`.
const EVALUATOR_PARAMS = new Set(["scope", "code"]);
const GLOBAL_ALIASES = new Set(["globalThis", "global", "self"]);

// `new Function` bodies are always sloppy, which `with` requires even inside a strict bundle.
const evaluate = new Function("scope", "code", "with (scope) { return eval(code); }");

function scopeFor(context) {
  return new Proxy(context, {
    has: (_, name) => typeof name === "symbol" || !EVALUATOR_PARAMS.has(name),
    get(target, name) {
      if (name === Symbol.unscopables) return undefined;
      if (name === "eval") return intrinsicEval;
      if (GLOBAL_ALIASES.has(name)) return target;
      return name in target ? target[name] : globalThis[name];
    },
    set(target, name, value) {
      target[name] = value;
      return true;
    },
  });
}

function assertContext(context) {
  if (!contexts.has(context)) {
    throw new TypeError('The "contextifiedObject" argument must be an vm.Context.');
  }
}

function createContext(sandbox = {}) {
  contexts.add(sandbox);
  return sandbox;
}

function runInContext(code, context) {
  assertContext(context);
  return evaluate.call(context, scopeFor(context), String(code));
}

function runInNewContext(code, sandbox = {}) {
  return runInContext(code, createContext(sandbox));
}

function runInThisContext(code) {
  return (0, eval)(String(code));
}

function compileFunction(code, params = [], { contextExtensions = [] } = {}) {
  const extensionFor = (name) => contextExtensions.find((each) => name in each);
  const scope = new Proxy({}, {
    has: (_, name) => typeof name === "string" && extensionFor(name) !== undefined,
    get: (_, name) => (name === Symbol.unscopables ? undefined : extensionFor(name)?.[name]),
    set(_, name, value) {
      extensionFor(name)[name] = value;
      return true;
    },
  });
  const factory = new Function("scope", `with (scope) { return function (${params.join(", ")}) {\n${code}\n}; }`);
  return factory(scope);
}

class Script {
  constructor(code) {
    this.code = String(code);
  }

  runInThisContext() {
    return runInThisContext(this.code);
  }

  runInContext(context) {
    return runInContext(this.code, context);
  }

  runInNewContext(sandbox) {
    return runInNewContext(this.code, sandbox);
  }
}

export const vm = {
  Script,
  createContext,
  isContext: (value) => contexts.has(value),
  runInContext,
  runInNewContext,
  runInThisContext,
  compileFunction,
};
