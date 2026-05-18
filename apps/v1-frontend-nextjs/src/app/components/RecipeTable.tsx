import React from "react";
import { Recipe } from "./recipeService"; 

interface RecipeTableProps {
  initialRecipes: Recipe[];
}

const RecipeTable = ({ initialRecipes }: RecipeTableProps) => {

  // Empty state: If the database is empty or the fetch failed gracefully
  if (!initialRecipes || initialRecipes.length === 0) {
    return (
      <div className="w-full text-center py-8">
        <div className="max-w-md mx-auto bg-gray-50 border border-gray-200 rounded-lg p-6">
          <svg className="mx-auto h-12 w-12 text-gray-400 mb-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
          </svg>
          <h3 className="text-lg font-semibold text-gray-900 mb-2">No Recipes Yet</h3>
          <p className="text-sm text-gray-600">Be the first to submit a recipe above!</p>
        </div>
      </div>
    );
  }

  return (
    <div className="w-full" style={{ fontFamily: "var(--font-montserrat-alternates)" }}>
      {/* Desktop View */}
      <div className="hidden md:block overflow-x-auto shadow-sm rounded-lg">
        <table className="min-w-full bg-white border-collapse">
          <thead className="bg-[color:var(--brown-dark)] text-white">
            <tr>
              <th className="py-4 px-6 text-left font-semibold border-r border-gray-600">Name</th>
              <th className="py-4 px-6 text-left font-semibold border-r border-gray-600">Recipe</th>
              <th className="py-4 px-6 text-left font-semibold border-r border-gray-600">Ingredients</th>
              <th className="py-4 px-6 text-left font-semibold">Description</th>
            </tr>
          </thead>
          <tbody>
            {initialRecipes.map((item: Recipe, index: number) => (
              <tr 
                // Fallback to index if DB ID is missing
                key={item.id || `recipe-${index}`} 
                className="border-b border-gray-200 odd:bg-[color:var(--table-bg-alt)] even:bg-[color:var(--table-bg)] hover:bg-gray-50 transition-colors"
              >
                <td className="py-4 px-6 font-semibold text-[color:var(--brown-dark)] border-r border-gray-200">{item.name}</td>
                <td className="py-4 px-6 text-[color:var(--brown-dark)] border-r border-gray-200">{item.recipe_name}</td>
                <td className="py-4 px-6 text-sm text-[color:var(--brown-dark)] border-r border-gray-200">
                  <div className="break-words">{item.ingredients}</div>
                </td>
                <td className="py-4 px-6 text-sm text-[color:var(--brown-dark)]">
                  <div className="break-words">{item.recipe_details}</div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {/* Mobile View */}
      <div className="md:hidden space-y-4">
        {initialRecipes.map((item: Recipe, index: number) => (
          <div 
            key={item.id || `recipe-mobile-${index}`} 
            className="p-4 rounded-lg border border-gray-200 odd:bg-[color:var(--table-bg-alt)] even:bg-[color:var(--table-bg)] shadow-sm"
          >
            <div className="space-y-3">
              <div>
                <h3 className="text-xs font-bold uppercase text-gray-500 tracking-wider">Name</h3>
                <p className="text-sm font-semibold text-[color:var(--brown-dark)]">{item.name}</p>
              </div>
              <div>
                <h3 className="text-xs font-bold uppercase text-gray-500 tracking-wider">Recipe</h3>
                <p className="text-sm text-[color:var(--brown-dark)]">{item.recipe_name}</p>
              </div>
              <div>
                <h3 className="text-xs font-bold uppercase text-gray-500 tracking-wider">Ingredients</h3>
                <p className="text-xs text-[color:var(--brown-dark)]">{item.ingredients}</p>
              </div>
              <div>
                <h3 className="text-xs font-bold uppercase text-gray-500 tracking-wider">Description</h3>
                <p className="text-xs text-[color:var(--brown-dark)]">{item.recipe_details}</p>
              </div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
};

export default RecipeTable;