const API_BASE = '/api'; 

export async function getRecipes() {
  try {
    const res = await fetch(`${API_BASE}/get_recipe`, {
      headers: { 'Accept': 'application/json' },
    });
    if (!res.ok) throw new Error(`Server Error: ${res.status}`);
    const data = await res.json();
    return Array.isArray(data) ? data : [];
  } catch (err) {
    console.error("❌ Error fetching data:", err);
    return [];
  }
}

export async function addRecipe(formData) {
  try {
    const newRecipe = {
      name: formData.get('name'),
      email: formData.get('email'),
      recipe_name: formData.get('recipe'),
      ingredients: formData.get('ingredients'),
      description_main: formData.get('description'),
    };

    const res = await fetch(`${API_BASE}/add_recipe`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(newRecipe),
    });

    if (!res.ok) throw new Error('Failed to add recipe');
    return { success: true };
  } catch (error) {
    console.error("❌ Error in addRecipe:", error);
    return { success: false, error: "Failed to submit recipe." };
  }
}
