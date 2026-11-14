SolidErrors::Engine.routes.draw do
  get "/", to: "errors#index", as: :root

  resources :errors, only: [:index, :show, :update, :destroy], path: "" do
    collection do
      patch :resolve
      delete :destroy_many
    end
  end
end
