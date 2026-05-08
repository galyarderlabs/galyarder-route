"use server";

import { NextResponse } from "next/server";
import fs from "fs/promises";
import path from "path";
import os from "os";
import { requireCliToolsAuth } from "@/lib/api/requireCliToolsAuth";
import {
  ensureCliConfigWriteAllowed,
  getCliPrimaryConfigPath,
  getCliRuntimeStatus,
} from "@/shared/services/cliRuntime";
import { createBackup } from "@/shared/services/backupService";
import { saveCliToolLastConfigured, deleteCliToolLastConfigured } from "@/lib/db/cliToolState";
import { cliModelConfigSchema } from "@/shared/validation/schemas";
import { isValidationFailure, validateBody } from "@/shared/validation/helpers";
import { getApiKeyById } from "@/lib/localDb";

const getQwenSettingsPath = () => getCliPrimaryConfigPath("qwen");
const getQwenDir = () => path.dirname(getQwenSettingsPath());
const getQwenEnvPath = () => path.join(getQwenDir(), ".env");

// Read current settings.json
const readSettings = async () => {
  try {
    const settingsPath = getQwenSettingsPath();
    const content = await fs.readFile(settingsPath, "utf-8");
    return JSON.parse(content);
  } catch (error: any) {
    if (error.code === "ENOENT") return null;
    throw error;
  }
};

// Read current .env file
const readEnv = async () => {
  try {
    const envPath = getQwenEnvPath();
    return await fs.readFile(envPath, "utf-8");
  } catch (error: any) {
    if (error.code === "ENOENT") return "";
    throw error;
  }
};

// Check if settings has GalyarderRoute config
const hasGalyarderRouteConfig = (settings: any) => {
  if (!settings || !settings.modelProviders) return false;
  const openai = settings.modelProviders.openai;
  if (!Array.isArray(openai)) return false;
  return openai.some((p: any) => {
    if (p.name?.includes("GalyarderRoute") || p.id === "galyarder-route") return true;
    if (!p.baseUrl) return false;
    try {
      const urlObj = new URL(p.baseUrl);
      const host = urlObj.hostname;
      const isDashScope =
        host === "dashscope.aliyuncs.com" || host.endsWith(".dashscope.aliyuncs.com");
      const isOpenAI = host === "api.openai.com" || host.endsWith(".openai.com");
      return !isDashScope && !isOpenAI;
    } catch {
      return true; // invalid URLs are treated as custom endpoints
    }
  });
};

// GET - Check Qwen CLI and read current settings
export async function GET(request: Request) {
  const authError = await requireCliToolsAuth(request);
  if (authError) return authError;

  try {
    const runtime = await getCliRuntimeStatus("qwen");

    if (!runtime.installed || !runtime.runnable) {
      return NextResponse.json({
        installed: runtime.installed,
        runnable: runtime.runnable,
        command: runtime.command,
        commandPath: runtime.commandPath,
        runtimeMode: runtime.runtimeMode,
        reason: runtime.reason,
        settings: null,
        message:
          runtime.installed && !runtime.runnable
            ? "Qwen Code CLI is installed but not runnable"
            : "Qwen Code CLI is not installed",
      });
    }

    const settings = await readSettings();

    return NextResponse.json({
      installed: runtime.installed,
      runnable: runtime.runnable,
      command: runtime.command,
      commandPath: runtime.commandPath,
      runtimeMode: runtime.runtimeMode,
      reason: runtime.reason,
      settings,
      hasGalyarderRoute: hasGalyarderRouteConfig(settings),
      settingsPath: getQwenSettingsPath(),
      envPath: getQwenEnvPath(),
    });
  } catch (error) {
    console.log("Error checking qwen settings:", error);
    return NextResponse.json({ error: "Failed to check qwen settings" }, { status: 500 });
  }
}

// POST - Write GalyarderRoute config to settings.json + .env
export async function POST(request: Request) {
  const authError = await requireCliToolsAuth(request);
  if (authError) return authError;

  let rawBody;
  try {
    rawBody = await request.json();
  } catch {
    return NextResponse.json(
      {
        error: {
          message: "Invalid request",
          details: [{ field: "body", message: "Invalid JSON body" }],
        },
      },
      { status: 400 }
    );
  }

  try {
    const writeGuard = ensureCliConfigWriteAllowed();
    if (writeGuard) {
      return NextResponse.json({ error: writeGuard }, { status: 403 });
    }

    // Extract keyId BEFORE validation — Zod strips unknown fields
    const keyId = typeof rawBody?.keyId === "string" ? rawBody.keyId.trim() : null;

    const validation = validateBody(cliModelConfigSchema, rawBody);
    if (isValidationFailure(validation)) {
      return NextResponse.json({ error: validation.error }, { status: 400 });
    }
    let { baseUrl, apiKey, model } = validation.data;

    // Resolve real key from DB by ID
    if (keyId) {
      try {
        const keyRecord = await getApiKeyById(keyId);
        if (keyRecord?.key) apiKey = keyRecord.key as string;
      } catch {
        /* non-critical */
      }
    }

    const resolvedApiKey = apiKey || "sk_galyarder_route";
    const resolvedModel = model || "coder-model";
    const normalizedBaseUrl = String(baseUrl || "")
      .trim()
      .replace(/\/+$/, "");
    const qwenDir = getQwenDir();
    const settingsPath = getQwenSettingsPath();
    const envPath = getQwenEnvPath();

    // Ensure directory exists
    await fs.mkdir(qwenDir, { recursive: true });

    // Backup current settings before modifying
    await createBackup("qwen", settingsPath);

    // --- Write API keys to ~/.qwen/.env ---
    let envContent = await readEnv();
    const envLines = envContent.split("\n").filter((line) => {
      // Remove old GalyarderRoute-related keys we're about to write
      return (
        !line.startsWith("OPENAI_API_KEY=") &&
        !line.startsWith("ANTHROPIC_API_KEY=") &&
        !line.startsWith("GEMINI_API_KEY=")
      );
    });

    envLines.push(`OPENAI_API_KEY=${resolvedApiKey}`);
    envLines.push(`ANTHROPIC_API_KEY=${resolvedApiKey}`);
    envLines.push(`GEMINI_API_KEY=${resolvedApiKey}`);

    await fs.writeFile(envPath, envLines.join("\n").trim() + "\n", "utf-8");

    // --- Write modelProviders to settings.json ---
    let existingConfig: Record<string, any> = {};
    try {
      const raw = await fs.readFile(settingsPath, "utf-8");
      existingConfig = JSON.parse(raw);
    } catch {
      // File doesn't exist or invalid JSON
    }

    if (!existingConfig.modelProviders) existingConfig.modelProviders = {};

    // openai provider — primary, supports all models via GalyarderRoute
    const openaiEntry = {
      id: resolvedModel,
      name: `${resolvedModel} (GalyarderRoute)`,
      envKey: "OPENAI_API_KEY",
      baseUrl: normalizedBaseUrl,
      generationConfig: {
        contextWindowSize: 200000,
      },
    };

    if (!existingConfig.modelProviders.openai) existingConfig.modelProviders.openai = [];
    const openaiProviders = existingConfig.modelProviders.openai;
    const openaiIdx = openaiProviders.findIndex(
      (p: any) => p && (p.baseUrl === normalizedBaseUrl || p.id === "galyarder-route")
    );
    if (openaiIdx >= 0) {
      openaiProviders[openaiIdx] = openaiEntry;
    } else {
      openaiProviders.push(openaiEntry);
    }

    // anthropic provider — for Claude models via GalyarderRoute
    const anthropicEntry = {
      id: "claude-sonnet-4-6",
      name: "Claude Sonnet 4.6 (GalyarderRoute)",
      envKey: "ANTHROPIC_API_KEY",
      baseUrl: normalizedBaseUrl,
      generationConfig: {
        contextWindowSize: 200000,
      },
    };

    if (!existingConfig.modelProviders.anthropic) existingConfig.modelProviders.anthropic = [];
    const anthropicProviders = existingConfig.modelProviders.anthropic;
    const anthropicIdx = anthropicProviders.findIndex(
      (p: any) => p && p.baseUrl === normalizedBaseUrl
    );
    if (anthropicIdx >= 0) {
      anthropicProviders[anthropicIdx] = anthropicEntry;
    } else {
      anthropicProviders.push(anthropicEntry);
    }

    // gemini provider — for Gemini models via GalyarderRoute
    const geminiEntry = {
      id: "gemini-3-flash",
      name: "Gemini 3 Flash (GalyarderRoute)",
      envKey: "GEMINI_API_KEY",
      baseUrl: normalizedBaseUrl,
    };

    if (!existingConfig.modelProviders.gemini) existingConfig.modelProviders.gemini = [];
    const geminiProviders = existingConfig.modelProviders.gemini;
    const geminiIdx = geminiProviders.findIndex((p: any) => p && p.baseUrl === normalizedBaseUrl);
    if (geminiIdx >= 0) {
      geminiProviders[geminiIdx] = geminiEntry;
    } else {
      geminiProviders.push(geminiEntry);
    }

    await fs.writeFile(settingsPath, JSON.stringify(existingConfig, null, 2), "utf-8");

    // Persist last-configured timestamp
    try {
      saveCliToolLastConfigured("qwen");
    } catch {
      /* non-critical */
    }

    return NextResponse.json({
      success: true,
      message: "Qwen Code config saved successfully!",
      settingsPath,
      envPath,
    });
  } catch (error) {
    console.log("Error updating qwen settings:", error);
    return NextResponse.json({ error: "Failed to update qwen settings" }, { status: 500 });
  }
}

// DELETE - Remove GalyarderRoute config from settings.json and .env
export async function DELETE(request: Request) {
  const authError = await requireCliToolsAuth(request);
  if (authError) return authError;

  try {
    const writeGuard = ensureCliConfigWriteAllowed();
    if (writeGuard) {
      return NextResponse.json({ error: writeGuard }, { status: 403 });
    }

    const settingsPath = getQwenSettingsPath();
    const envPath = getQwenEnvPath();

    // Backup current settings before resetting
    await createBackup("qwen", settingsPath);

    // --- Clean settings.json ---
    let existingConfig: Record<string, any> = {};
    try {
      const raw = await fs.readFile(settingsPath, "utf-8");
      existingConfig = JSON.parse(raw);
    } catch (error: any) {
      if (error.code === "ENOENT") {
        return NextResponse.json({
          success: true,
          message: "No settings file to reset",
        });
      }
      throw error;
    }

    // Remove GalyarderRoute entries from each provider type
    const providerTypes = ["openai", "anthropic", "gemini"];
    for (const type of providerTypes) {
      if (Array.isArray(existingConfig.modelProviders?.[type])) {
        existingConfig.modelProviders[type] = existingConfig.modelProviders[type].filter(
          (p: any) => !p.name?.includes("GalyarderRoute") && p.id !== "galyarder-route"
        );
        // Remove empty provider arrays
        if (existingConfig.modelProviders[type].length === 0) {
          delete existingConfig.modelProviders[type];
        }
      }
    }

    // Clean up empty modelProviders
    if (existingConfig.modelProviders && Object.keys(existingConfig.modelProviders).length === 0) {
      delete existingConfig.modelProviders;
    }

    await fs.writeFile(settingsPath, JSON.stringify(existingConfig, null, 2), "utf-8");

    // --- Clean .env ---
    const RESET_ENV_KEYS = ["OPENAI_API_KEY", "ANTHROPIC_API_KEY", "GEMINI_API_KEY"];

    try {
      let envContent = await fs.readFile(envPath, "utf-8");
      const envLines = envContent
        .split("\n")
        .filter((line) => !RESET_ENV_KEYS.some((key) => line.startsWith(`${key}=`)));

      await fs.writeFile(envPath, envLines.join("\n").trim() + "\n", "utf-8");
    } catch {
      // .env doesn't exist — nothing to clean
    }

    // Clear last-configured timestamp
    try {
      deleteCliToolLastConfigured("qwen");
    } catch {
      /* non-critical */
    }

    return NextResponse.json({
      success: true,
      message: "GalyarderRoute settings removed from Qwen Code",
    });
  } catch (error) {
    console.log("Error resetting qwen settings:", error);
    return NextResponse.json({ error: "Failed to reset qwen settings" }, { status: 500 });
  }
}
