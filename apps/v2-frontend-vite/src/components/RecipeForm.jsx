import React, { useState } from "react";
import { addRecipe } from "../recipeService";

const RecipeForm = ({ onRecipeSubmitted }) => {
  const [isSubmitting, setIsSubmitting] = useState(false);

  const handleSubmit = async (e) => {
    e.preventDefault();
    setIsSubmitting(true);

    const formData = new FormData(e.target);
    const result = await addRecipe(formData);

    if (result.success) {
      alert("Transmitted successfully to V2 Backend!");
      e.target.reset();
      if (onRecipeSubmitted) onRecipeSubmitted();
    } else {
      alert(result.error || "Submission failed.");
    }
    setIsSubmitting(false);
  };

  return (
    <div className="w-full max-w-6xl mx-auto py-12 px-8 mb-12 bg-[#1A1A1A] rounded-xl border border-[#333] shadow-[0_0_20px_rgba(50,205,50,0.05)]">
      <div className="text-center mb-10">
        <h2 className="text-3xl font-bold text-[#32CD32] font-['Montserrat_Alternates']">
          Submit Recipe Payload
        </h2>
      </div>

      <form className="space-y-6" onSubmit={handleSubmit}>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
          <input required name="name" placeholder="Chef Name" className="w-full bg-[#242424] border border-[#444] rounded-lg p-4 text-white focus:outline-none focus:border-[#32CD32]" />
          <input required name="email" type="email" placeholder="Contact Email" className="w-full bg-[#242424] border border-[#444] rounded-lg p-4 text-white focus:outline-none focus:border-[#32CD32]" />
          <input required name="recipe" placeholder="Recipe Designation" className="w-full bg-[#242424] border border-[#444] rounded-lg p-4 text-white focus:outline-none focus:border-[#32CD32]" />
        </div>
        
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          <textarea required name="ingredients" rows="5" placeholder="Ingredients (Comma Separated Array)" className="w-full bg-[#242424] border border-[#444] rounded-lg p-4 text-white focus:outline-none focus:border-[#32CD32]"></textarea>
          <textarea required name="description" rows="5" placeholder="Execution Protocol (Instructions)" className="w-full bg-[#242424] border border-[#444] rounded-lg p-4 text-white focus:outline-none focus:border-[#32CD32]"></textarea>
        </div>

        <div className="flex justify-center pt-4">
          <button type="submit" disabled={isSubmitting} className="px-12 py-3 text-black font-bold rounded-lg transition-all bg-[#32CD32] hover:bg-[#228B22] disabled:opacity-50 tracking-widest">
            {isSubmitting ? "TRANSMITTING..." : "EXECUTE SUBMISSION"}
          </button>
        </div>
      </form>
    </div>
  );
};

export default RecipeForm;
