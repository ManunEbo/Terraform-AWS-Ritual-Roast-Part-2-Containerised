'use server'

// 1. Define the data structure for strict type safety in production builds
export interface Recipe {
  id?: number;
  name: string;
  email: string;
  recipe_name: string;
  recipe_details: string; // Matched to the DB distillation in Flask
  ingredients?: string;
  created_at?: string;
}

// 2. Securely reference the Internal ALB injected by Terraform
// Fallback is provided for local development outside of Docker
const BACKEND_URL = process.env.BACKEND_URL || 'http://localhost:5000';

/**
 * Fetches recipes from the private Flask backend.
 * This runs entirely Server-Side inside your AWS VPC.
 */
export async function getRecipes(): Promise<Recipe[]> {
  try {
    const controller = new AbortController();
    
    // Infrastructure timeout: prevent the Fargate container from hanging forever
    const timeoutId = setTimeout(() => {
      controller.abort();
    }, 10000); 

    const res = await fetch(`${BACKEND_URL}/api/get_recipe`, {
      signal: controller.signal,
      cache: 'no-store', // Next.js equivalent of ensuring real-time data bypasses the CDN cache
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    });

    clearTimeout(timeoutId);

    if (!res.ok) {
      throw new Error(`Flask Server Error: ${res.status} ${res.statusText}`);
    }

    const data = await res.json();

    // Validation: Ensure we actually received an array
    if (Array.isArray(data)) {
      return data;
    } else {
      throw new Error("Invalid data format received from Flask server");
    }
  } catch (err) {
    if (err instanceof Error && err.name === 'AbortError') {
      console.error("❌ Fetch timed out - Internal ALB or Flask backend is unreachable.");
    } else {
      console.error("❌ Error fetching data from Flask:", err);
    }
    
    // Graceful degradation: Return an empty array so the UI renders gracefully
    // rather than crashing the entire Next.js application with a 500 error.
    return [];
  }
}

/**
 * Submits a new recipe to the private Flask backend.
 * This acts as a secure proxy between the browser form and the DB.
 */
export async function addRecipe(formData: FormData): Promise<{ success: boolean; error?: string }> {
  try {
    // Distill the FormData into a clean object matching the API expectations
    const newRecipe = {
      name: formData.get('name') as string,
      email: formData.get('email') as string,
      recipe_name: formData.get('recipe_name') as string,
      ingredients: formData.get('ingredients') as string,
      description_main: formData.get('description_main') as string,
    };

    const res = await fetch(`${BACKEND_URL}/api/add_recipe`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(newRecipe),
    });

    if (!res.ok) {
      throw new Error(`Failed to add recipe: ${res.statusText}`);
    }

    return { success: true };
  } catch (error) {
    console.error("❌ Error in addRecipe server action:", error);
    return { success: false, error: "Failed to submit recipe to the database." };
  }
}