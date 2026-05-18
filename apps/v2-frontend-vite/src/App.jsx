import React, { useState, useEffect } from 'react';
import Header from './components/Header';
import Banner from './components/Banner';
import RecipeForm from './components/RecipeForm';
import RecipeTable from './components/RecipeTable';
import { getRecipes } from './recipeService';

function App() {
  const [recipes, setRecipes] = useState([]);
  const [loading, setLoading] = useState(true);

  const fetchDatabase = async () => {
    setLoading(true);
    const data = await getRecipes();
    setRecipes(data);
    setLoading(false);
  };

  useEffect(() => {
    fetchDatabase();
  }, []);

  return (
    <div className="min-h-screen flex flex-col bg-[#121212] text-gray-200">
      <Header />
      <Banner />
      
      <main className="flex-grow w-full py-12">
        <RecipeForm onRecipeSubmitted={fetchDatabase} />
        
        {loading ? (
          <div className="text-center py-12 text-[#32CD32] animate-pulse font-bold tracking-widest">
            SYNCING WITH V2 BACKEND...
          </div>
        ) : (
          <RecipeTable initialRecipes={recipes} />
        )}
      </main>

      <footer className="w-full py-6 text-center bg-[#0a0a0a] border-t border-[#333] font-bold text-[#3E2723]">
        <span className="text-[#32CD32]">RITUAL ROAST V2</span> | KUBERNETES CANARY BUILD
      </footer>
    </div>
  );
}

export default App;
