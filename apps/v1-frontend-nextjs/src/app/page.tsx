import OurChoices from "./components/OurChoices";
import RecipeTable from "./components/RecipeTable";
import RecipeForm from "./components/RecipeForm";
import Banner from "./components/Banner";
import CountdownTimer from "./components/CountdownTimer";
import { getRecipes } from "./components/recipeService"; // Import the server action

export default async function Home() {
  // 1. Fetch data securely on the server inside the AWS VPC 
  // before the page is ever sent to the user's browser.
  const recipes = await getRecipes();

  return (
    <main className="min-h-screen bg-white">
      <Banner />
      
      <CountdownTimer />
      
      {/* RecipeForm is our Client Component that proxies data back to the server */}
      <RecipeForm />
      
      {/* RecipeTable is our Server Component. We inject the fetched data 
        directly into it. No loading spinners needed!
      */}
      <RecipeTable initialRecipes={recipes} />
      
      <OurChoices />  
    </main>
  );
}